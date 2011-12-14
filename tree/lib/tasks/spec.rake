namespace :spec do
  task :report do
    dir = Dir.getwd

    data = {}
    %w(spec:preload test:units test:functionals test:api:json test:api:xml test:integration).each do |task|
      run_task = task
      run_task = 'test:api' if task == 'test:api:xml' && Rake::Task.tasks.find { |t| t.name == task }.nil?

      start = Time.now
      pass = begin
        Rake::Task[run_task].invoke
        true
      rescue StandardError => e
        false
      rescue Exception => e
        raise e unless task == 'spec:preload'
        false
      end
      duration = Time.now - start

      puts "#{task} #{pass ? 'pass' : 'fail'}ed in #{'%.2f' % duration} seconds."
      data[task] = [pass, duration]
      break if task == 'spec:preload' && !pass
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
