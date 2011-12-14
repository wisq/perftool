#!/usr/bin/env ruby

$LOAD_PATH << File.dirname(__FILE__) + '/lib'
require 'perf/bisect'

require 'set'

class PerfWatch
  def initialize
    @redis = Redis.new
    @bisect = Perf::Bisect.new
    @bisect.get_versions('fdfac297cdcbeb0323542bc387c93224a432c941', 'master')
  end

  def run
    old_reports = current_reports
    highlight = []

    loop do
      output(highlight)

      ready = false
      until ready do
        sleep(10)
        new_reports = current_reports
        if new_reports.count != old_reports.count
          gone = old_reports - new_reports
          gone.each do |sha|
            puts "Vanished: #{sha}"
            @bisect.versions.find { |v| v.sha == sha }.reset
            ready = true
          end

          highlight = new_reports - old_reports
          highlight.each do |sha|
            puts "Just finished: #{sha}"
            @bisect.versions.find { |v| v.sha == sha }.reset
            ready = true
          end
        end
        old_reports = new_reports
      end
    end
  end

  def output(highlights)
    complete = @bisect.versions.select(&:complete?)
    first_bi, second_bi = @bisect.next_bisect
    (1..complete.count - 1).map do |index|
      first  = complete[index - 1]
      second = complete[index]
      first_i  = @bisect.versions.index(first)
      second_i = @bisect.versions.index(second)

      time_diff = (second.total_runtime - first.total_runtime).to_i
      time_str  = (time_diff >= 0 ? '+' : '-') + time_diff.abs.to_s

      flags = []
      flags << '___' if first_bi  == second
      flags << '^^^' if second_bi == second
      flags << '***' if highlights.include?(second.sha)

      printf "%s: %5ss over %5s commits %s\n", second.sha[0,7], time_str, second_i - first_i, flags.join(' ')
    end
    $stdout.flush
  end

  def current_reports
    @redis.keys('perf-timings-*').map {|k| k.split('-').last}.to_set
  end
end

PerfWatch.new.run
