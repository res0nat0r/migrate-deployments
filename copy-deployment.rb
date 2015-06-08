#!/usr/bin/env ruby

require 'optparse'
require 'json'
require 'pry'
require 'right_api_client'
require 'pry-debugger'

@options = {}
@server_templates = {}
@old_deployment, @new_deployment = nil

creds = JSON.parse(File.open("#{ENV['HOME']}/.rsc").read)

@api = RightApi::Client.new(
  :email        => creds['Email'],
  :password     => creds['api_password'],
  :account_id   => creds['Account'],
  :enable_retry => true,
  :timeout      => nil)

OptionParser.new do |opts|
opts.banner = "Usage: #{$0} [options]"

opts.on("-s", "--src <id>", "Source account ID") {|s| @options[:src] = s}
opts.on("-d", "--dst <id>", "Destination account ID") {|d| @options[:dst] = d}
opts.on("-e", "--deployment <id>", "Source deployment ID to be migrated") {|e| @options[:deployment] = e}
opts.on("-g", "--group <id>", "Export ServerTemplates to Publishing Group ID") {|g| @options[:group] = g}
end.parse!

def main
  check_if_deployment_exists
  publish_templates
  import_templates
  create_deployment
  create_servers
end


# ----- Check if deployment with matching name exists in destination account -----
def check_if_deployment_exists
  @api.account_id = @options[:src]
  @old_deployment = @api.deployments(:id => @options[:deployment], :view => "inputs_2_0").show

  @api.account_id = @options[:dst]
  if @api.deployments.index(:filter => ["name==#{@old_deployment.name}"]).length != 0
    $stderr.puts "ERROR: Deployment with name \"#{@old_deployment.name}\" already exists in account #{@options[:dst]}\n"
    exit 1
  end
end



# ----- Publish all unique ServerTemplates in a deployment -----
def publish_templates
  # Use soure account ID to discover deployment
  @api.account_id = @options[:src]
  @old_deployment = @api.deployments(:id => @options[:deployment], :view => "inputs_2_0").show
  servers = @old_deployment.show.servers.index
  puts "Discovered deployment: #{@old_deployment.name} ...\n\n"

  # find href of current servers servertemplate and set it as the key in the server_templates hash
  servers.each do |server|
    puts "Discovered server: #{server.name} ..."

    if server.next_instance.show.server_template.show.revision == 0
      $stderr.puts "ERROR: Cannot publish a HEAD version of a ServerTemplate. Please commit first."
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

    puts "Publishing: \"#{st.name}\" to group: #{@options[:group]} ..."
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
def import_templates
  # Use destination account ID
  @api.account_id = @options[:dst]

  puts "\n"
  # Import each ServerTemplate and store the new location
  @server_templates.keys.each do |server_template|
    # Grab ID number from /api/server_templates/:id
    id = @server_templates[server_template]['publication_url'].split('/').last
    response = @api.publications(:id => id).import

    puts "Importing: \"#{response.show.name}\" to account: #{@options[:dst]}"

    @server_templates[server_template]['new_st_url'] = response.show.href
  end
end



# ------ Create a new deployment in the dst account -----
def create_deployment
  @api.account_id = @options[:dst]

  params = {
    :deployment => {
      :name        => @old_deployment.name,
      :description => @old_deployment.description
    }
  }

  puts "\nCreating deployment: \"#{params[:deployment][:name]}\" in account: #{@options[:dst]} ...\n\n"

  @api.account_id = @options[:dst]
  result = @api.deployments.create(params)
  @new_deployment = result.href
end




# ----- Recreate existing servers from old deployment in new account -----
def create_servers
  # use "rsc" tool to get detailed deployment + server  view from api 1.6, not supported by right_api_client
  old_deployment = JSON.parse(`rsc -a #{@options[:src]} cm16 show /api/deployments/#{@options[:deployment]} view=full`)

  old_deployment['servers'].each do |server|
    @api.account_id = @options[:src]
    name             = server['next_instance']['name']

    puts "Creating server: #{name} ...\n"

    cloud            = find_cloud(server['next_instance']['links']['cloud']['href'], name)
    @api.account_id = @options[:src]

    ssh_key          = find_ssh_key(cloud, server['next_instance']['links']['ssh_key'], name)
    @api.account_id = @options[:src]


    mci              = server['next_instance']['links']['computed_multi_cloud_image']['href']
    instance_type    = server['next_instance']['links']['instance_type']['href']
    old_st_url       = server['next_instance']['server_template']['href']
    new_st_url       = @server_templates[old_st_url]['new_st_url']
    old_mci_url      = @api.resource(mci).show.href
    old_mci          = @api.resource(old_mci_url).show
    inputs           = @api.resource(server['next_instance']['href']).show.inputs
    inputs_hash      = {}

    # Find matching MCI from src account in dst account
    @api.account_id = @options[:dst]
    new_mci_url     =  @api.resource(new_st_url).show.links.select {|l| l['rel'] == 'multi_cloud_images'}.first['href']
    new_mci_list    = @api.resource(new_mci_url).index
    new_mci         = new_mci_list.select{|mci| mci.name == old_mci.name && mci.revision == old_mci.revision}.first.href
    
    # create input key/value pairs
    @api.account_id = @options[:src]
    inputs.index.each do |input|
      # Array input format type isn't correct and must be changed to a json array.
      # More info here: http://reference.rightscale.com/api1.5/resources/ResourceInputs.html#multi_update
      if input.value =~ /^array:/
        array = input.value.sub(/^array:/, "").split(",")
        array.map {|a| a.sub!(/^/, "\"text:").sub!(/$/, "\"")}
        new_array = array.join(",")
        new_array.sub!(/^/, "array:[")
        new_array.sub!(/$/, "]")
        inputs_hash[input.name] = new_array
      else
        inputs_hash[input.name] = input.value
      end
    end
    
    # Create server
    params = { 
      :server => {
        :name => name,
        :deployment_href => @new_deployment,
        :instance => {
          :cloud_href => cloud,
          :server_template_href => new_st_url,
          :inputs => inputs_hash
    }}}

    @api.account_id = @options[:dst]
    @api.servers.create(params)
  end
end


# ----- Find cloud -----
def find_cloud(old_cloud_href, name)
  @api.account_id = @options[:dst]
  cloud = @api.clouds.index.select {|cloud| cloud.href == old_cloud_href}.first

  if cloud
    puts "Found matching cloud: \"#{cloud.name}\" for server: \"#{name}\"\n"
    return cloud.href
  else
    puts "\nNo matching cloud found for: \"#{name}\"\n"
    puts "Choose One:"
    i = 0
    @api.clouds.index.each do |cloud|
      puts "[#{i}] #{cloud.name}\n"
      i += 1
    end
    print "\n? "
    return @api.clouds.index[gets.chomp.to_i].href
  end
end

# ----- Find SSH key -----
def find_ssh_key(new_cloud, ssh_key, name)
  if not ssh_key
    puts "Original host does not have an ssh key set, leaving blank ...\n"
    return ""
  end
 
  @api.account_id = @options[:src]
  old_ssh_key = @api.resource(ssh_key['href'])

  @api.account_id = @options[:dst]
  new_ssh_keys = @api.resource(new_cloud).ssh_keys
  new_ssh_key = new_ssh_keys.index.select {|key| key.name == old_ssh_key.name}.first

  if new_ssh_key
    puts "Found matching ssh key for \"#{name}\" using ...\n"
    return new_ssh_key.href
  elsif
    new_ssh_keys.index.length == 0
    puts "No ssh keys found...leaving blank.\n\n"
    return ""
  else
    puts "Matching ssh key not found for: \"#{name}\"\n\n"
    puts "Choose One:"
    print "\n? "
    i = 0
    new_ssh_keys.index.each  do |key|
      puts "[#{i}] #{key.name}\n"
      i += 1
      return new_ssh_keys.index[gets.chomp.to_i].href
    end
  end
end

main()

__END__

# ----- Find SSH key -----
def find_ssh_key(new_cloud, ssh_key, name)
  
  if not ssh_key
    return ""
  end

  @api.account_id = @options[:src]
  old_ssh_key = @api.resource(ssh_key)

  @api.account_id = @options[:dst]
  new_ssh_keys = @api.resource(new_cloud).ssh_keys
  new_ssh_key = new_ssh_keys.index.select {|key| key.name == old_ssh_key.name}.first

  if new_ssh_key
    puts "Found matching ssh key for \"#{name}\" using ...\n"
    return new_ssh_key.href
  elsif
    new_ssh_keys.index.length == 0
    puts "No ssh keys found...leaving blank.\n\n"
    return ""
  else
    puts "Matching ssh key not found for: \"#{name}\"\n\n"
    puts "Choose One:"
    print "\n? "
    i = 0
    new_ssh_keys.index.each  do |key|
      puts "[#{i}] #{key.name}\n"
      i += 1
      return new_ssh_keys.index[gets.chomp.to_i].href
    end
  end
end

main()
