require 'perf'
require 'fileutils'

class Perf::Version
  include Perf::Config

  attr_reader :sha

  SPEC_REPORT = 'tmp/spec_report.yml'

  def initialize(sha, redis = Redis.new)
    @redis = redis
    @sha   = sha
  end

  def inspect
    "<#{self.class}:#{@sha}>"
  end

  def process_spec_report(report)
    @spec_report = report
    @redis.set(spec_report_key, report.to_yaml)
  end

  def process_timings_report(report)
    @timings_report = report
    @redis.set(timings_report_key, report.to_yaml)
  end

  def merge_timings_reports
    report = get_timings_report_keys.inject({}) do |report, key|
      part = YAML.load(@redis.get(key))
      report.deep_merge(part)
    end
    raise 'No timings report' if report.empty?
    report
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
    @spec_report ||= get_spec_report
  end

  def timings_report
    @timings_report ||= get_timings_report
  end

  def complete?
    !(spec_report.empty? || timings_report.empty?)
  end

  def get_spec_report
    yaml = @redis.get(spec_report_key)
    return {} if yaml.nil?
    YAML.load(yaml)
  end

  def get_timings_report
    yaml = @redis.get(timings_report_key)
    return {} if yaml.nil?
    YAML.load(yaml)
  end

  def spec_report_key
    "perf-spec-report-#{sha}"
  end

  def timings_report_key
    "perf-timings-report-#{sha}"
  end

  def run
    Dir.chdir(WORK_TREE) do
      sh %w{git reset --hard}
      sh %w{git clean -f -d -e tmp}
      sh 'git', 'checkout', @sha
      patch_gemfile
      patch_rakefile
      patch_migrations
      patch_plugins
      patch_code

      sh 'rsync', '-rt', COPY_TREE + '/', './'

      File.unlink(SPEC_REPORT) if File.exist?(SPEC_REPORT)
      delete_timings_reports

      sh %w{bundle check} rescue sh %w{bundle install}
      sh %w{bundle exec rake --trace spec:report}

      process_spec_report(YAML.load_file(SPEC_REPORT))
      process_timings_report(merge_timings_reports)
    end
  end

  def patch_gemfile
    gemfile = File.read('Gemfile').lines.select do |line|
      case line
      when /gem .rails_parallel.,/
        false
      when /gem .rack-perftools_profiler.,/
        false
      else
        true
      end
    end

    gemfile.each do |line|
      case line
      when /^gem .activemerchant.,/
        line.sub!('d8c4f61', '202bdfc')
        line.sub!('Soleone', 'Shopify') if line =~ /:tag => /
      when /^gem .liquid.,/
        line.sub!('b890674', '4819eb1')
      end
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

  def patch_migrations
    patch_user_logins
    ['db/migrate/20110722185820_cyclechimp_quickify_extension_maintenance_job.rb'].each do |file|
      File.unlink(file) if File.exist?(file)
    end
  end

  def patch_user_logins
    file = 'db/migrate/20100929154720_create_user_logins.rb'
    return unless File.exist?(file)
    migration = File.read(file)
    migration.sub!(', :options => "ENGINE=Archive"', '')
    File.open(file, 'w') { |fh| fh.puts migration }
  end

  def patch_plugins
    patch_ripn
  end

  def patch_ripn
    file = 'vendor/plugins/request_in_process_name/init.rb'
    init = File.read(file).lines.map do |line|
      line.chomp!
      if line.include?(':include, RequestInProcessName')
        line += " unless Rails.env.test? && $0.start_with?('rails_parallel')"
      end
      line
    end
    File.open(file, 'w') { |fh| fh.puts init }
  end

  def patch_code
    patch_code_qbms
  end

  def patch_code_qbms
    bad = [
      '18fab0d53d047a8a8d74cd71197b1360cdf602d5',
      'f34239effe43bb44ba161190c26a5d846659bd43',
      '681503b0a8b8fe6140868c22333ec55a9a3a0522',
      '72f2a49857800242afc886286c355169115d65c1'
    ]
    sh %w{git cherry-pick fdb603d39ad5a1893debf95bd72a6f91c5542422} if bad.include?(@sha)
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
      when %r{wisq/bin$} then true
      else false
      end
    end
    paths.join(':')
  end

  def reset
    instance_variables.each do |var|
      instance_variable_set(var, nil) unless [:@redis, :@sha].include?(var)
    end
  end
end
