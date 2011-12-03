require 'perf'
require 'perf/version'

class Perf::Bisect
  attr_reader :versions

  def initialize
    @redis = Redis.new

    file = Pathname.new(__FILE__)
    @tree_path = (file.dirname + '../../tree').realpath
    @work_path = Pathname.new('../work').realpath
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
    Dir.chdir(@work_path.to_s) do
      @versions = shell_lines(
        'git', 'log', '--format=%H', "#{first}^..#{last}"
      ).reverse.map do |sha|
        Perf::Version.new(sha.chomp, @redis, @tree_path)
      end
    end
  end

  def run(first, last)
    Dir.chdir(@work_path.to_s)
    get_versions(first, last)

    [@versions.first, @versions.last].each { |v| v.run unless v.complete? }

    while gap = biggest_gap do
      first, second = gap
      midpoint = bisect(first, second)
      p [first.sha, second.sha]
      p [midpoint.sha]
      raise 'midpoint complete?' if midpoint.complete?
      midpoint.run
    end
  end

  def biggest_gap
    complete = @versions.select(&:complete?)

    pairs = (1 .. complete.count - 1).map do |index|
      [complete[index - 1], complete[index]]
    end

    nonadjacent_pairs = pairs.select do |first, second|
      @versions.index(second) - @versions.index(first) > 1
    end

    nonadjacent_pairs.sort_by do |first, second|
      0 - (second.total_runtime - first.total_runtime).abs
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
