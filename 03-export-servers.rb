#!/usr/bin/env ruby

require 'json'

unless ARGV.length == 1
  puts "need deployment"
  exit 1
end

deployment = JSON.parse(File.open('stuff/show.deployment.full.json', 'r').read)
deployment_id = ARGV[0]

deployment['servers'].each do |server|
  STDERR.puts "Discovered server: #{server['name']}"
end

deployment['servers'].each do |server|
  name             = server['next_instance']['name']
  cloud            = server['next_instance']['links']['cloud']['href']
  mci              = server['next_instance']['links']['computed_multi_cloud_image']['href']
  instance_type    = server['next_instance']['links']['instance_type']['href']
  ssh_key          = server['next_instance']['links']['ssh_key']['href']
  server_template  = server['next_instance']['server_template']['href']
  # subnets
  # security_groups
  #  datacenter       = server['next_instance']['links']['datacenter']['href']

  # stefhen-crap-clone 571903004
  cmd = [
    "rsc", "cm15", "create", "/api/servers",
    "server[instance][multi_cloud_image_href]=#{mci}",
    "server[instance][server_template_href]=#{server_template}",
    "server[instance][instance_type_href]=#{instance_type}",
    #server[instance][inputs]=map
    "server[instance][ssh_key_href]=#{ssh_key}",
    #server[instance][subnet_hrefs][]=[]string
    "server[instance][cloud_href]=#{cloud}",
    "server[instance][multi_cloud_image_href]=#{mci}",
    "server[deployment_href]=#{deployment_id}",
    "server[name]=#{name}"
  ]

  result = IO.popen(cmd, 'r+') { |io|
    io.close_write
    io.read
  }
  puts "#{result}"
end
