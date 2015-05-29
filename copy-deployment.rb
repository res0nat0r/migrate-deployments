#!/usr/bin/env ruby

require 'optparse'
require 'json'
require 'pry'
require 'right_api_client'

@options = {}
@server_templates = {}

creds = JSON.parse(File.open("#{ENV['HOME']}/.rsc").read)

@api = RightApi::Client.new(
  :email        => creds['Email'],
  :password     => creds['api_password'],
  :account_id   => creds['Account'],
  :enable_retry => true,
  :timeout      => nil)

@api.log("/Users/stefhenhovland/work/stuff/rsc/migration-steps/log")

OptionParser.new do |opts|
opts.banner = "Usage: #{$0} [options]"

opts.on("-s", "--src <id>", "Source account ID") {|s| @options[:src] = s}
opts.on("-d", "--dst <id>", "Destination account ID") {|d| @options[:dst] = d}
opts.on("-e", "--deployment <id>", "Source deployment ID to be migrated") {|e| @options[:deployment] = e}
opts.on("-g", "--group <id>", "Export ServerTemplates to Publishing Group ID") {|g| @options[:group] = g}
end.parse!

def main
  publish()
end

# --- PUBLISH ---
# Iterate through all servers in a deployment and publish all unique ServerTemplates
def publish
  deployment = @api.deployments(:id => @options[:deployment]).show
  servers = deployment.show.servers.index

  puts "Discovered deployment: #{deployment.name} ...\n\n"

  # find href of current servers servertemplate and set it as the key in the server_templates hash
  servers.each do |server|
    puts "Discovered server: #{server.name} ..."

    if server.next_instance.show.server_template.show.revision == 0
      puts "ERROR: Cannot publish a HEAD version of a ServerTemplate. Please commit first."
      exit 1
    end
    @server_templates[server.next_instance.show.server_template.show.href] =
      {"name" => server.next_instance.show.server_template.show.name}
  end
  puts "\nDiscovered unique ServerTemplates:\n\n"
  @server_templates.keys.each do |st|
    puts "#{@server_templates[st]['name']}"
  end

  # Publish each unique ServerTemplate
  @server_templates.keys.each do |server_template|
    st = @api.resource(server_template)

    puts "Publishing: #{st.name} to group: #{@options[:group]} ..."
    response = st.publish(
      "account_group_hrefs" => [ @options[:group] ],
      "descriptions[long]" => st.description,
      "descriptions[short]" => st.description[0..255],
      "descriptions[notes]" => "Auto imported from account #{@options[:src]}"
    )
    # Add publication URL to hash
    @server_templates[server_template]["publication_url"] = response.show.href
  end
end

def import

end


__END__

main()

server_templates.keys.each do |st|
  url = server_templates[st]['publication_url']

  STDERR.puts "Importing #{url} to account: #{dst_account} ..."

  cmd = ["rsc", "--account", "#{dst_account}", "--xh", "Location", "cm15", "import", "#{url}"]

  new_st_url = IO.popen(cmd, 'r+') { |io|
    io.close_write
    io.read
  }
  server_templates[st]['new_st_url'] = new_st_url
end
puts "\n"
