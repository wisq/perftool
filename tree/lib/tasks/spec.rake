namespace :spec do
  task :report do
    dir = Dir.getwd

    data = %w(spec:preload test:units test:functionals test:api test:api:json test:integration).collect do |task|
      start = Time.now
      pass = begin
        Rake::Task[task].invoke
        true
      rescue => e
        false
      end
      duration = Time.now - start

      puts "#{task} #{pass ? 'pass' : 'fail'}ed in #{'%.2f' % duration} seconds."
      [task, pass, duration]
    end

    File.open(dir + '/tmp/spec_report.yml', 'w') do |fh|
      fh.puts data.to_yaml
    end
  end

  Rake::TestTask.new(:preload) do |t|
    t.pattern = 'test/spec_preload.rb'
    t.libs << 'test'
    t.verbose = true
  end
end
