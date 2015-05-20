#!/usr/bin/env ruby

unless ARGV.length == 2
  puts "Usage: #{$0} /api/deployments/:id /api/account_groups/:id\n\n"
  puts "/api/deployments/:id is the deployment ID to export."
  puts "/api/account_groups/:id is the account group where the ServerTemplates are to be published."
  exit 1
end

server_templates = `rsc cm16 show #{ARGV[0]} view=full | jq '.instances[].server_template.href' | sort | uniq`.split(/\n/)
server_templates.map! { |i| i.gsub(/"/,'') } # remove inner quote marks
account = `rsc cm16 show #{ARGV[0]} view=full | jq '.links.account.id'`
publications = []

STDERR.puts "Discovered unique ServerTemplates:\n\n"
server_templates.each { |st| STDERR.puts st }; puts "\n"

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

STDERR.puts "\nPUBLISHED:\n"
publications.each { |p| puts p }
