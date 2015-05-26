#!/usr/bin/env ruby

require 'getoptlong'

opts = GetoptLong.new(
  [ "--src", GetoptLong::REQUIRED_ARGUMENT ],
  [ "--dst", GetoptLong::REQUIRED_ARGUMENT ],
  [ "--deployment", GetoptLong::REQUIRED_ARGUMENT ],
  [ "--help", GetoptLong::NO_ARGUMENT]
)

help = <<-EOF
#{$0} [options]

--src        Source account ID to copy deployment from.
--dst        Destination account ID to copy deployment to.
--deployment Deployment ID to copy from: /api/deployments/:id
EOF

opts.each do |opt, arg|
  case opt
  when "--src"
    src_deployment = arg
  when "--dst"
    dst_deployment = arg
  when "--deployment"
    deployment = arg
  end
end

unless ARGV.length == 3
  puts help
  exit 1
end


__END__
server_templates = `rsc cm16 show #{ARGV[0]} view=full | jq '.instances[].server_template.href' | sort | uniq`.split(/\n/)
server_templates.map! { |i| i.gsub(/"/,'') } # remove inner quote marks
account = `rsc cm16 show #{ARGV[0]} view=full | jq '.links.account.id'`
publications = []

STDERR.puts "Discovered unique ServerTemplates:\n\n"
server_templates.each { |st| STDERR.puts st }; STDERR.puts "\n"

server_templates.each do |st|
  description = `rsc cm15 show #{st} | jq '.description'`
  short_description = description[0..255]
  name = `rsc cm15 show #{st} | jq '.name'`
  notes = "Auto imported from account: #{account}"

  STDERR.puts "Publishing: #{name.chomp} to group: #{ARGV[1].split('/').last} ...\n"

  cmd = ["rsc", "--xh", "Location", "cm15", "publish", "#{st}",
    "account_group_hrefs[]=/api/account_groups/#{ARGV[1]}",
    "descriptions[short]=#{short_description}",
    "descriptions[notes]=#{notes}",
    "descriptions[long]=#{description}"]

  result = IO.popen(cmd, 'r+') { |io|
    io.close_write
    io.read
  }
  publications.push(result)
end

STDERR.puts "\nPUBLISHED:"
publications.each { |p| puts p }
