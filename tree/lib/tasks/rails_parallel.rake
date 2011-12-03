if ENV['PARALLEL']
  begin
    Rake::Task['test:prepare'].clear_prerequisites
  rescue
    Rake::Task['db:test:prepare'].clear_prerequisites
  end

  namespace :parallel do
    task :launch do
      RailsParallel::Rake.launch
    end

    namespace :db do
      task :setup => ['db:drop', 'db:create', 'parallel:db:reset', 'db:schema:load', 'db:migrate']

      task :load => :environment do
        RailsParallel::Rake.load_current_db
      end

      task :reset do
        cp "db/schema.versioned.rb", "db/schema.rb"
      end
    end
  end
end
