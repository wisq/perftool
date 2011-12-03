require 'perf'
require 'fileutils'

class Perf::Version
  attr_reader :sha

  SPEC_REPORT = 'tmp/spec_report.yml'

  def initialize(sha, redis = Redis.new, tree = nil)
    @redis = redis
    @tree  = tree
    @sha   = sha
  end

  def process_spec_report(report)
    @spec_report = report
    @redis.set(spec_report_key, report.to_yaml)
  end

  def process_timings_report
    @timings_report = get_timings_report_keys.inject({}) do |report, key|
      part = YAML.load(@redis.get(key))
      report.deep_merge(part)
    end
    raise 'No timings report' if @timings_report.empty?
    @redis.set(timings_report_key, @timings_report.to_yaml)
  end

  def total_runtime
    total = 0.0
    timings_report.each do |test, classes|
      classes.each do |cls, time|
        total += time
      end
    end
    total
  end

  def spec_report
    @spec_report || get_spec_report
  end

  def timings_report
    @timings_report || get_timings_report
  end

  def complete?
    spec_report && timings_report
  end

  def get_spec_report
    yaml = @redis.get(spec_report_key)
    YAML.load(yaml) unless yaml.nil?
  end

  def get_timings_report
    yaml = @redis.get(timings_report_key)
    YAML.load(yaml) unless yaml.nil?
  end

  def spec_report_key
    "perf-spec-report-#{sha}"
  end

  def timings_report_key
    "perf-timings-report-#{sha}"
  end

  def run
    sh %w{git reset --hard}
    sh %w{git clean -f -d -e tmp}
    sh 'git', 'checkout', @sha
    patch_gemfile
    patch_rakefile
    patch_user_logins

    sh 'rsync', '-rt', @tree.to_s + '/', './'

    File.unlink(SPEC_REPORT) if File.exist?(SPEC_REPORT)
    delete_timings_reports

    sh %w{bundle check} rescue sh %w{bundle install}
    sh %w{bundle exec rake --trace spec:report}

    process_spec_report(YAML.load_file(SPEC_REPORT))
    process_timings_report
  end

  def patch_gemfile
    gemfile = File.read('Gemfile').lines.reject { |l| l =~ /gem .rails_parallel.,/ }
    gemfile.each do |line|
      line.sub!('d8c4f61', '202bdfc')
    end
    gemfile << 'gem "rails_parallel", "0.1.3", :path => "/home/wisq/parallel/rails_parallel", :require => false'
    File.open('Gemfile', 'w') { |fh| fh.puts(*gemfile) }
  end

  def patch_rakefile
    found = false
    rakefile = File.read('Rakefile').lines.map do |line|
      line.chomp!
      case line
      when /^require.*config\/application/
        raise if found
        found = true
        [line, "require 'rails_parallel/rake' if ENV['PARALLEL']"]
      when /^require 'rails_parallel'/
        nil
      else
        line
      end
    end.compact.flatten
    raise 'Line not found, old Rakefile?' unless found
    File.open('Rakefile', 'w') { |fh| fh.puts(*rakefile) }
  end

  def patch_user_logins
    file = 'db/migrate/20100929154720_create_user_logins.rb'
    return unless File.exist?(file)
    migration = File.read(file)
    migration.sub!(', :options => "ENGINE=Archive"', '')
    File.open(file, 'w') { |fh| fh.puts migration }
  end

  def get_timings_report_keys
    @redis.keys('timings-report-*')
  end

  def delete_timings_reports
    get_timings_report_keys.each do |key|
      @redis.del(key)
    end
  end

  class CommandFailed < StandardError; end

  def sh(*cmd)
    env = {
      :HOME => ENV['HOME'],
      :PATH => @path ||= get_sh_path,
      :RBENV_VERSION => 'ree',
      :PARALLEL => 1,
      :RP_TIMINGS_REPORT => 1,
    }.map { |k, v| "#{k}=#{v}" }
    full_cmd = ['/usr/bin/env', '-i', env, cmd].flatten
    system(*full_cmd)
    raise CommandFailed unless $?.success?
  end

  def get_sh_path
    paths = ENV['PATH'].split(':').select do |p|
      case p
      when %r{\.rbenv/bin} then true
      when %r{\.rbenv/shims} then true
      when %r{^(/usr)?/s?bin$} then true
      else false
      end
    end
    paths.join(':')
  end
end
