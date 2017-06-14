# thanks http://robots.thoughtbot.com/post/11957424161/test-rake-tasks-like-a-boss

require 'rake'

shared_context 'rake' do
  subject(:task)  { rake[task_name] }

  let(:rake)      { Rake::Application.new }
  let(:task_name) { self.class.top_level_description }
  let(:task_path) { "lib/tasks/#{task_name.split(':').first}" }

  before do
    Rake.application = rake
    Rake.application
        .rake_require(task_path,
                      [File.join(File.dirname(__FILE__), '..', '..')])

    Rake::Task.define_task(:environment)
  end
end
