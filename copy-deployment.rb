#!/usr/bin/env ruby

require 'optparse'
require 'json'
require 'pry'
require 'right_api_client'

@options = {}
@server_templates = {}
@deployment = nil

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
  import()
  recreate()
end






# ----- Publish all unique ServerTemplates in a deployment -----
def publish
  # Use soure account ID to discover deployment
  @api.account_id = @options[:src]
  @deployment = @api.deployments(:id => @options[:deployment], :view => "inputs_2_0").show
  servers = @deployment.show.servers.index
  puts "Discovered deployment: #{@deployment.name} ...\n\n"

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
  puts "\n"
  @server_templates.keys.each do |server_template|
    st = @api.resource(server_template)

    puts "Publishing: #{st.name} to group: #{@options[:group]} ..."
    response = st.publish(
      "account_group_hrefs" => [ "/api/account_groups/#{@options[:group]}" ],
      "descriptions[long]"  => st.description,
      "descriptions[short]" => st.description[0..255],
      "descriptions[notes]" => "Auto imported from account #{@options[:src]}"
    )
    # Add publication URL to hash
    @server_templates[server_template]['publication_url'] = response.show.href
  end
end






# ----- Import published ServerTemplates to destination account -----
def import
  # Use destination account ID
  @api.account_id = @options[:dst]

  puts "\n"
  # Import each ServerTemplate and store the new location
  @server_templates.keys.each do |server_template|
    # Grab ID number from /api/server_templates/:id
    id = @server_templates[server_template]['publication_url'].split('/').last
    response = @api.publications(:id => id).import

    puts "Importing: #{response.show.name} ..."

    @server_templates[server_template]['new_st_url'] = response.show.href
  end
end






# ----- Recreate existing servers in old deployment in new account -----
def recreate
  # Use src account ID
  @api.account_id = @options[:src]

  # use "rsc" tool to get detailed deployment view from api 1.6, not supported by right_api_client
  deployment = JSON.parse(`rsc -a #{@options[:src]} cm16 show /api/deployments/#{@options[:deployment]} view=full`)

  deployment['servers'].each do |server|
    name             = server['next_instance']['name']
    cloud            = server['next_instance']['links']['cloud']['href']
    mci              = server['next_instance']['links']['computed_multi_cloud_image']['href']
    instance_type    = server['next_instance']['links']['instance_type']['href']
    ssh_key          = server['next_instance']['links']['ssh_key']['href']
    old_st_url       = server['next_instance']['server_template']['href']
    new_st_url       = @server_templates[old_st_url]['new_st_url']
    old_mci_url      = @api.resource(mci).show.href
    old_mci          = @api.resource(old_mci_url).show
    inputs           = @api.resource(server['next_instance']['href']).show.inputs

    @api.account_id = @options[:dst]

    # Find matching MCI from src account in dst account
    new_mci_url  =  @api.resource(new_st_url).show.links.select {|l| l['rel'] == 'multi_cloud_images'}.first['href']
    new_mci_list = @api.resource(new_mci_url).index
    new_mci      = new_mci_list.select{|m| m.name == old_mci.name && m.revision == old_mci.revision}
  end
end

main()

__END__
  new_mci_list.each do |mci|
    if ((old_mci['name'] == mci['name'])  && (old_mci['revision'] == mci['revision']))
      mci['links'].each do |link|
        new_mci = link['href'] if link['rel'] == 'self'
      end
    end





  # --- MCI ---
  # Find matching MCI being used on this instance in the new ST and use it
  new_mcis_url, new_mci_list, new_mci = nil
  old_mci = JSON.parse(`rsc --account #{src_account} cm15 show #{mci}`)

  new_st['links'].each do |link|
    new_mcis_url = link['href'] if link['rel'] == "multi_cloud_images"
  end

  new_mci_list = JSON.parse(`rsc --account #{dst_account} cm15 index #{new_mcis_url}`)


#  old_st = JSON.parse(`rsc --account #{@options[:src]} cm15 show #{old_st_url}`)
#  new_st = JSON.parse(`rsc --account #{dst_account} cm15 show #{new_st_url}`)

# --- Create Instances ---
deployment['servers'].each do |server|
  name             = server['next_instance']['name']
  cloud            = server['next_instance']['links']['cloud']['href']
  mci              = server['next_instance']['links']['computed_multi_cloud_image']['href']
  instance_type    = server['next_instance']['links']['instance_type']['href']
  ssh_key          = server['next_instance']['links']['ssh_key']['href']
  old_st_url       = server['next_instance']['server_template']['href']
  new_st_url       = server_templates[old_st_url]['new_st_url']
  next_instance    = server['next_instance']['href']
  inputs           = JSON.parse(`rsc --account #{src_account} cm15 show #{next_instance} view=full_inputs_2_0`)['inputs']
  old_st = JSON.parse(`rsc --account #{src_account} cm15 show #{old_st_url}`)
  new_st = JSON.parse(`rsc --account #{dst_account} cm15 show #{new_st_url}`)

  # --- MCI ---
  # Find matching MCI being used on this instance in the new ST and use it
  new_mcis_url, new_mci_list, new_mci = nil
  old_mci = JSON.parse(`rsc --account #{src_account} cm15 show #{mci}`)

  new_st['links'].each do |link|
    new_mcis_url = link['href'] if link['rel'] == "multi_cloud_images"
  end

  new_mci_list = JSON.parse(`rsc --account #{dst_account} cm15 index #{new_mcis_url}`)

  new_mci_list.each do |mci|
    if ((old_mci['name'] == mci['name'])  && (old_mci['revision'] == mci['revision']))
      mci['links'].each do |link|
        new_mci = link['href'] if link['rel'] == 'self'
      end
    end
  end
  # --- END MCI ---
binding.pry
  puts "Creating instance: #{name} ..."

  cmd = [
    "echo", "rsc", "--account", "#{dst_account}",
    "cm15", "create", "/api/servers",
    "server[name]=#{name}",
    "server[instance][multi_cloud_image_href]=#{new_mci}",
    "server[instance][server_template_href]=#{new_st_url}",
    "server[instance][instance_type_href]=#{instance_type}",
    "server[instance][cloud_href]=#{cloud}",
    "server[deployment_href]=#{new_deployment}",
#    "server[instance][inputs]=#{JSON.dump(inputs)}"
    "server[instance][inputs]={'activemq/mirror':'http://storage.googleapis.com/rightscale-hello/activemq/apache-activemq-5.10.0-bin.tar.gz'}"

  ]

  STDERR.puts "Creating #{name} ..."

  result = IO.popen(cmd, 'r+') { |io|
    io.close_write
    io.read
  }
  puts "#{result}"
end




=begin
  servers = @deployment.show.servers.index

  servers.each do |server|
    name = server.next_instance.show.name
    cloud = server.next_instance.show.links.select {|l| l['rel'] == 'cloud'}.first['href']
    mci = server.next_instance.show.links.select {|l| l['rel'] == 'multi_cloud_image'}.first['href'] #TODO: fix?

    mci = server.next_instance.show.links.select {|l| l['rel'] == 'computed_multi_cloud_image'}.first['href']
=end
