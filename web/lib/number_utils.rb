
module NumberUtils
  extend self

  # Converts size specifications like '1G', '2 MB', ... to number of bytes
  def byte_spec_to_int(s)
    if s =~ /([0-9 ]+)\s*([kKMGT])B?/
      num = $1
      multiplier = $2
      num = num.gsub(' ', '').to_i
      multiplier =
        case multiplier
        when 'k', 'K'
          1024
        when 'M'
          1024 * 1024
        when 'G'
          1024 * 1024 * 1024
        when 'T'
          1024 * 1024 * 1024 * 1024
        else
          raise "Unrecognized multiplier in size specification: #{$2}"
        end
      num * multiplier
    else
      raise "Unrecognized size specification: #{s}"
    end
  end
end
