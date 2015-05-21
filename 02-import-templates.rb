#!/usr/bin/env ruby

require 'getoptlong'

account = nil
opts = GetoptLong.new ( [ '--account', GetoptLong::OPTIONAL_ARGUMENT ] )

opts.each do |opt, val|
  case opt
  when '--account'
    account = val
  end
end

unless ARGV.length == 1
  puts "Usage: #{$0} [--account <account id>] <file>\n\n"
  puts "<file> containins URLS in form: /api/publication/:id"
  puts "<account id> is an alternate account to import into"
  exit 1
end

file = File.open(ARGV[0], "r").read.split(/\n/)

file.each do |template|
  if template =~ /\/api\/publications\/\d+/
    puts "Importing: #{template} ..."
    if account
      `rsc --account #{account} cm15 import #{template}`
    else
      `rsc cm15 import #{template}`
    end
  end
end
