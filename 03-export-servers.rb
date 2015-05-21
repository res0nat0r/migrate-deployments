#!/usr/bin/env ruby

require 'json'
require 'pry'

deployment = JSON.parse(File.open('stuff/show.deployment.full.json', 'r').read)

deployment['servers'].each do |server|
  puts "Discovered server: #{server['name']}"
end

deployment['servers'].each do |server|
  name = server['name']
  cloud_name = server['links']['cloud']['name']
  cloud_href = server['links']['cloud']['href']
  mci = server['links']['multi_cloud_image']['href']
  datacenter = server['links']['datacenter']['href']
  instance_type = server['links']['instance_type']['href']
  #security_groups
  ssh_key = server['links']['ssh_key']['href']
  # subnets
  server_template = server['links']['href']
end
