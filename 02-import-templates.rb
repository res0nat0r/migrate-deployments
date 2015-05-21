#!/usr/bin/env ruby

unless ARGV.length == 1
  puts "Usage: #{$0} <server template list>"
  puts "Where: <server template list> is a file containing URLS in form: /api/publication/:id"
  exit 1
end

file = File.open(ARGV[0], "r").read.split(/\n/)

file.each do |template|
  if template =~ /\/api\/publications\/\d+/
    puts "Importing #{template} ..."
  end
end
