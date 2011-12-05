require 'perf'
require 'perf/version'

class Perf::Bisect
  include Perf::Config

  attr_reader :versions

  def initialize
    @redis = Redis.new

    file = Pathname.new(__FILE__)
  end

  def shell_lines(*cmd)
    out = nil
    IO.popen('-') do |fh|
      if fh
        out = fh.readlines
      else
        exec(*cmd)
        raise 'exec failed'
      end
    end

    raise "#{cmd.first} failed" unless $?.success?
    out
  end

  def get_versions(first, last)
    Dir.chdir(WORK_TREE) do
      @versions = shell_lines(
        'git', 'log', '--format=%H', "#{first}^..#{last}"
      ).reverse.map do |sha|
        Perf::Version.new(sha.chomp, @redis)
      end
    end
  end

  def run(first, last)
    Dir.chdir(WORK_TREE)
    get_versions(first, last)

    [@versions.first, @versions.last].each { |v| v.run unless v.complete? }

    while next_b = next_bisect do
      first, second = next_b
      midpoint = bisect(first, second)
      p [first.sha, second.sha]
      p [midpoint.sha]
      raise 'midpoint complete?' if midpoint.complete?
      midpoint.run
    end
  end

  def next_bisect
    complete = @versions.select(&:complete?)

    pairs = (1 .. complete.count - 1).map do |index|
      first  = complete[index - 1]
      second = complete[index]

      first_index  = @versions.index(first)
      second_index = @versions.index(second)

      distance = second_index - first_index

      [first, second, distance] unless distance == 1
    end.compact

    pairs.sort_by do |first, second, distance|
      time_diff = second.total_runtime - first.total_runtime
      0 - distance/5 - time_diff.abs
    end.first
  end

  def bisect(first, second)
    first_i  = @versions.index(first)
    second_i = @versions.index(second)
    midpoint = first_i + (second_i - first_i) / 2
    p [first_i, second_i, midpoint]
    @versions[midpoint]
  end
end
