#!/usr/bin/env ruby

require 'getoptlong'
require 'json'
require 'set'

require 'pry'

opts = GetoptLong.new(
  [ "--src", GetoptLong::REQUIRED_ARGUMENT ],
  [ "--dst", GetoptLong::REQUIRED_ARGUMENT ],
  [ "--group", GetoptLong::REQUIRED_ARGUMENT],
  [ "--deployment", GetoptLong::REQUIRED_ARGUMENT ]
)

src_account, dst_account, group = nil
deployment, deployment_name, deployment_description = nil
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

#TODO: add help

# ----- Publish ServerTemplates ------

# Get deployment info
deployment             = JSON.parse(`rsc -a #{src_account} cm16 show #{deployment} view=full`)
server_templates       = Set.new
deployment_name        = deployment['name']
deployment_description = deployment['description']
publications           = []

# Find unique server templates
deployment['instances'].each do |instance|
  if instance['server_template']['version'] == 0
    STDERR.puts "ERROR: Cannot commit a HEAD version of a ServerTemplate."
    STDERR.puts "Ensure all ServerTemplates have been committed."
    exit 1
  end
  server_templates.add(instance['server_template']['href'])
end

STDERR.puts "Discovered unique ServerTemplates:\n"
server_templates.each { |st| STDERR.puts st }; STDERR.puts "\n"

server_templates.each do |st|
  response = JSON.parse(`rsc cm15 show #{st}`)
  description = response['description']
  short_description = description[0..255]
  name = response['name']
  notes = "Auto imported from account: #{src_account}"

  STDERR.puts "Publishing: #{name} to group: #{group.split('/').last} ..."

  # Publish ServerTemplate
  cmd = ["rsc", "--xh", "Location", "cm15", "publish", "#{st}",
    "account_group_hrefs[]=/api/account_groups/#{group}",
    "descriptions[short]=#{short_description}",
    "descriptions[notes]=#{notes}",
    "descriptions[long]=#{description}"
  ]

  result = IO.popen(cmd, 'r+') { |io|
    io.close_write
    io.read
  }
  publications.push(result)
end

STDERR.puts "\nPUBLISHED:"
publications.each { |p| puts p }; STDERR.puts "\n"


# --- Import ServerTemplates ---

#  `rsc --account #{dst_account} cm15 import #{pub}`
publications.each do |pub|
  STDERR.puts "Importing #{pub} to account: #{dst_account} ..."

  cmd = ["rsc", "--account", "#{dst_account}", "cm15", "import", "#{pub}"]
  result = IO.popen(cmd, 'r+') { |io|
    io.close_write
    io.read
  }
end
puts "\n"

# --- Recreate new Deployment ---

STDERR.puts "Creating new deployment: #{deployment_name} in account: #{dst_account} ..."

cmd = ["rsc", "--account", "#{dst_account}", "cm15", "create",
  "/api/deployments", "deployment[name]=#{deployment_name}",
  "deployment[description]=#{deployment_description}"
]
  result = IO.popen(cmd, 'r+') { |io|
    io.close_write
    io.read
  }
  STDERR.puts "#{result}"
