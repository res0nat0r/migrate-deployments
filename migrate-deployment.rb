#!/usr/bin/env ruby

require 'getoptlong'
require 'json'
require 'pry'

opts = GetoptLong.new(
  [ "--src", GetoptLong::REQUIRED_ARGUMENT ],
  [ "--dst", GetoptLong::REQUIRED_ARGUMENT ],
  [ "--group", GetoptLong::REQUIRED_ARGUMENT],
  [ "--deployment", GetoptLong::REQUIRED_ARGUMENT ]
)

src_account, dst_account, group = nil
new_deployment, deployment, deployment_name, deployment_description = nil
help = <<-EOF
#{$0} [options]

--src        Source account ID to copy deployment from.
--dst        Destination account ID to copy deployment to.
--group      Group to publish ServerTemplate to: /api/account_groups/:id
--deployment Deployment ID to copy from: /api/deployments/:id
EOF

opts.each do |opt, arg|
  case opt
  when "--src"
    src_account = arg
  when "--dst"
    dst_account = arg
  when "--group"
    group = arg
  when "--deployment"
    deployment = arg
  end
end

#TODO: add help error message and arg parsing

# ----- Publish ServerTemplates ------

# Get deployment info
deployment             = JSON.parse(`rsc -a #{src_account} cm16 show #{deployment} view=full`)
server_templates       = {}
deployment_name        = deployment['name']
deployment_description = deployment['description']

# Find unique server templates
deployment['instances'].each do |instance|
  if instance['server_template']['version'] == 0
    STDERR.puts "ERROR: Cannot commit a HEAD version of a ServerTemplate."
    STDERR.puts "Ensure all ServerTemplates have been committed."
    exit 1
  end
  server_templates[instance['server_template']['href']] = nil
end

STDERR.puts "Discovered unique ServerTemplates:\n"
server_templates.keys.each { |st| STDERR.puts st }; STDERR.puts "\n"

server_templates.keys.each do |st|
  response = JSON.parse(`rsc cm15 show #{st}`)
  description = response['description']
  short_description = description[0..255]
  name = response['name']
  notes = "Auto imported from account: #{src_account}"

  STDERR.puts "Publishing: #{name} to group: #{group.split('/').last} ..."

  # Publish ServerTemplate
  cmd = ["rsc", "--account", "#{src_account}",
    "--xh", "Location", "cm15", "publish", "#{st}",
    "account_group_hrefs[]=/api/account_groups/#{group}",
    "descriptions[short]=#{short_description}",
    "descriptions[notes]=#{notes}",
    "descriptions[long]=#{description}"
  ]

  publication_url = IO.popen(cmd, 'r+') { |io|
    io.close_write
    io.read
  }
  server_templates[st] = {"publication_url" => publication_url }
end

#STDERR.puts "\nPUBLISHED:"
#publications.each { |p| puts p }; STDERR.puts "\n"

# --- Import ServerTemplates ---

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

# --- Create new Deployment ---

STDERR.puts "Creating new deployment: #{deployment_name} in account: #{dst_account} ..."

cmd = ["rsc", "--account", "#{dst_account}", "--xh", "Location",
  "cm15", "create", "/api/deployments",
  "deployment[name]=#{deployment_name}",
  "deployment[description]=#{deployment_description}"
]
new_deployment = IO.popen(cmd, 'r+') { |io|
  io.close_write
  io.read
}

# --- Create Instances ---

deployment['servers'].each do |server|
  name             = server['next_instance']['name']
  cloud            = server['next_instance']['links']['cloud']['href']
  mci              = server['next_instance']['links']['computed_multi_cloud_image']['href']
  instance_type    = server['next_instance']['links']['instance_type']['href']
  ssh_key          = server['next_instance']['links']['ssh_key']['href']
  old_st_url       = server['next_instance']['server_template']['href']
  new_st_url       = server_templates[old_st_url]['new_st_url']
  # subnets
  # security_groups
  # inputs

  old_st = JSON.parse(`rsc --account #{src_account} cm15 show #{old_st_url}`)
  new_st = JSON.parse(`rsc --account #{dst_account} cm15 show #{new_st_url}`)

  puts "Creating instance: #{name} ..."

  binding.pry
end











__END__



  cmd = [
    "rsc", "--account", "#{dst_account}",
    "cm15", "create", "/api/servers",
    "server[name]=#{name}",
    "server[instance][multi_cloud_image_href]=#{mci}",
    "server[instance][server_template_href]=#{new_st_url}",
    "server[instance][instance_type_href]=#{instance_type}",
    "server[instance][cloud_href]=#{cloud}",
    "server[instance][multi_cloud_image_href]=#{mci}",
    "server[deployment_href]=#{new_deployment}"
    #server[instance][inputs]=map
    # server[instance][subnet_hrefs][]=[]string
    # "server[instance][ssh_key_href]=#{ssh_key}",
  ]

  STDERR.puts "Creating #{name} ..."

  result = IO.popen(cmd, 'r+') { |io|
    io.close_write
    io.read
  }
  puts "#{result}"
end
