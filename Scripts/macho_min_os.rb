#!/usr/bin/env ruby
# Best-effort minimum iOS version from Mach-O (including static archives).

MH_MAGIC = 0xFEEDFACE
MH_MAGIC_64 = 0xFEEDFACF
FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_64 = 0xCAFEBABF
LC_BUILD_VERSION = 0x32
LC_VERSION_MIN_IPHONEOS = 0x25

def read_u32_le(data, offset)
  data[offset, 4].unpack1("L<")
end

def read_u32_be(data, offset)
  data[offset, 4].unpack1("N")
end

def read_u64(data, offset)
  data[offset, 8].unpack1("Q<")
end

def parse_build_version(data, offset)
  return nil if offset + 16 > data.bytesize
  _cmd, _cmdsize, _platform, minos, _sdk = data[offset, 20].unpack("L<L<L<L<L<")
  major = (minos >> 16) & 0xFFFF
  minor = (minos >> 8) & 0xFF
  [major, minor]
end

def parse_version_min(data, offset)
  return nil if offset + 12 > data.bytesize
  _cmd, _cmdsize, version, _sdk = data[offset, 16].unpack("L<L<L<L<")
  major = (version >> 16) & 0xFFFF
  minor = (version >> 8) & 0xFF
  [major, minor]
end

def min_os_from_mach_o(data)
  magic_be = read_u32_be(data, 0)
  magic_le = read_u32_le(data, 0)
  slices = []

  if [FAT_MAGIC, FAT_MAGIC_64].include?(magic_be)
    nfat = read_u32_be(data, 4)
    offset = 8
    is64 = magic_be == FAT_MAGIC_64
    nfat.times do
      if is64
        _cpu, _sub, slice_off, slice_size, _align = data[offset, 32].unpack("N2Q2N")
        offset += 32
      else
        _cpu, _sub, slice_off, slice_size, _align = data[offset, 20].unpack("N5")
        offset += 20
      end
      slices << data[slice_off, slice_size]
    end
  else
    slices << data
  end

  best = nil
  slices.each do |sl|
    next if sl.bytesize < 32
    mag = read_u32_le(sl, 0)
    next unless [MH_MAGIC, MH_MAGIC_64].include?(mag)
    is64 = mag == MH_MAGIC_64
    ncmds = read_u32_le(sl, 16)
    cmd_off = is64 ? 32 : 28
    ncmds.times do
      break if cmd_off + 8 > sl.bytesize
      cmd = read_u32_le(sl, cmd_off)
      cmdsize = read_u32_le(sl, cmd_off + 4)
      parsed =
        case cmd
        when LC_BUILD_VERSION then parse_build_version(sl, cmd_off)
        when LC_VERSION_MIN_IPHONEOS then parse_version_min(sl, cmd_off)
        end
      if parsed
        if best.nil?
          best = parsed
        else
          best = [[best[0], parsed[0]].max, [best[1], parsed[1]].max]
        end
      end
      cmd_off += cmdsize
    end
  end
  best
end

def min_os_from_archive(data)
  return nil unless data.start_with?("!<arch>\n")
  pos = 8
  best = nil
  while pos + 60 <= data.bytesize
    header = data[pos, 60]
    break unless header.end_with?("`\n")
    name = header[0, 16].strip
    size = header[48, 10].strip.to_i
    member_start = pos + 60
    member = data[member_start, size]
    unless name.end_with?("/") || name == "__.SYMDEF"
      parsed = min_os_from_mach_o(member)
      best = parsed if parsed && (best.nil? || parsed[0] > best[0] || (parsed[0] == best[0] && parsed[1] > best[1]))
    end
    pos = member_start + size + (size.odd? ? 1 : 0)
  end
  best
end

path = ARGV[0] or abort("usage: #{$PROGRAM_NAME} <mach-o-path>")
data = File.binread(path)
version = min_os_from_archive(data) || min_os_from_mach_o(data)
abort unless version
major, minor = version
puts minor.positive? ? "#{major}.#{minor}" : "#{major}.0"
