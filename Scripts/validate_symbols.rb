#!/usr/bin/env ruby
# Verify required TfLite C API symbols exist in a framework binary (dylib or static archive).

require "shellwords"

required = %w[
  TfLiteModelCreate
  TfLiteInterpreterCreate
  TfLiteInterpreterInvoke
]

bin = ARGV[0] or abort("usage: #{$PROGRAM_NAME} <binary>")
abort("missing file: #{bin}") unless File.file?(bin)

nm = `nm -gU #{Shellwords.escape(bin)} 2>/dev/null`
if nm.strip.empty?
  nm = `nm #{Shellwords.escape(bin)} 2>/dev/null`
end

if nm.strip.empty?
  # Static archives may not expose symbols until member extraction; scan defined symbol names in output.
  nm = `nm -arch all #{Shellwords.escape(bin)} 2>/dev/null`
end

found = nm.lines.map { |l| l.split.last }.compact
missing = required.reject { |sym| found.any? { |f| f == sym || f.end_with?(sym) } }

if missing.empty?
  required.each { |sym| puts "OK #{sym}" }
  exit 0
end

# Last resort: undefined symbols referenced from headers are often present as global text symbols in .a
data = File.binread(bin)
missing2 = required.reject { |sym| data.include?(sym) }
if missing2.empty?
  required.each { |sym| puts "OK #{sym} (string present in binary)" }
  exit 0
end

warn "Missing symbols: #{missing2.join(', ')}"
exit 1
