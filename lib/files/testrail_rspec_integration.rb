require "rspec"
require_relative "testrail_operations"

module TestRailRSpecIntegration
  # This class responsible for communicating a test run back to testrail.
  # The status of a test example is NOT set until the 'after' hooks run.
  # Because the 'after' hook is not meant for observing the status of examples.
  # Thus you can NOT run an after block to get the completion status.
  # For a better explanation see:
  # https://github.com/rspec/rspec-core/issues/2011

  # For pushing results up to an existing test run in TestRail, no matter whether the test run is independent
  # or grouped under a test plan
  # # This is different from simply creating a stand-alone test run from the results of the test.
  # The tricky part about this is Jenkins run rspecs on multiple processes with different batches of
  # rspec tests.
  
  @@total_count = 0
  @@run_count = 0
  @@skip_count = 0

  class TestRailPlanFormatter
    RSpec::Core::Formatters.register self, :example_passed, :example_pending, :example_failed, :start, :stop
    public
    @@cases = []

    def initialize(out)
      @out = out
    end

    def self.set_product(product)
      @@product = product
    end

    def set_test_run_id(run_id)
      @@run_id = run_id
    end

    def test_id_key
      case @@product
        when :bridge
          :testrail_id
        when :canvas
          :test_id
      end
    end

    # Gets whether the formatter is active or not.
    # We don't want to push results up to test rail for instance if --dry-run is specified on the command line.
    def active
      !RSpec.configuration.dry_run
    end

    # This gets called before all tests are run
    def start(_start_notification)
      # It's been verified that these 4 environment variables already exist
      # These three are not actively used in this class, but their presence governs whether
      # this class is instantiated and used in the first place.

      if is_for_test_rail_run
        @testrail_run_id = ENV["TESTRAIL_RUN_ID"]
      elsif !ENV["TESTRAIL_PLAN_ID"].nil?
        @testrail_plan_id  = ENV["TESTRAIL_PLAN_ID"]
        @testrail_run_name = ENV["TESTRAIL_RUN"]
        if is_for_test_rail_plan # run on jenkins
          @testrail_run_id   = ENV["TESTRAIL_ENTRY_RUN_ID"]
          @testrail_entry_id = ENV["TESTRAIL_ENTRY_ID"]
        else # run locally, and only one thread
          ids = TestRailOperations.create_test_plan_entry(@testrail_plan_id, @testrail_run_name, include_all_cases: true)
          @testrail_run_id   = ids[:run_id]
          @testrail_entry_id = ids[:entry_id]
        end
      end

      # Initialize the batch size for test rail batching based on environment variable.
      # One test is the default, in case people don't want to batch or haven't provided the variable.
      if !ENV["TESTRAIL_BATCH_SIZE"].nil?
        @batch_size = ENV["TESTRAIL_BATCH_SIZE"]
      else
        @batch_size = 1
      end

      # Pull down ALL the test cases from testrail. Granted this is more than what rspec will actually
      # execute. But there is no safe way to append a test case to a test run in a parallel environment.
      # The Testrail API is just too limited.
      puts "Using test run ID: #{@testrail_run_id}"
      puts "Using test entry ID: #{@testrail_entry_id}"

      puts "Count of skipped tests: #{TestRailRSpecIntegration.get_skip_count}"
      puts "Count of tests to be run: #{TestRailRSpecIntegration.get_run_count}"
      puts "Count of tests that entered filter: #{TestRailRSpecIntegration.get_total_count}"

      puts "Batching test results in groups of #{@batch_size}"
      @test_case_hash = TestRailOperations.get_test_run_cases(@testrail_run_id)
      # save the test case ID's that were actually executed
      @executed_test_ids = []

      # Need a class variable for after suite hooks to post results,
      # since the after suite hooks are defined outside the class
      set_test_run_id(@testrail_run_id)
    end

    # This gets called after all tests are run
    def stop(_examples_notification)
      if @testrail_plan_id
        # Need to prune un-executed tests from the test run on testrail
        if is_for_test_rail_plan # run on jenkins, multiple threads doing this
          # Need to dump a list of executed tests so unexecuted tests can be pruned later (on testrail)
          # after all the rspec tests are done.
          File.open("executed_tests_#{Process.pid}.json", 'w') do |f|
            f.puts @executed_test_ids.to_json
          end
          # Another process will take the json file and use it to prune the test run.
        else # run locally, and only one thread
          # prune the test cases to only what was run
          response = TestRailOperations.keep_only(@testrail_plan_id, @testrail_entry_id, @executed_test_ids)
        end
      elsif !ENV["TESTRAIL_RUN_ID"].nil?
        # Results were already pushed to an existing testrail run. Nothing more to do here, we are done! :)
      else
        puts "Unknown condition"
      end
    end

    # This gets called after all `after` hooks are run after each example is completed
    def example_finished(notification)
      return unless active
      example = notification.example
      result = example.execution_result
      testrail_ids = example.metadata[test_id_key]

      return unless testrail_ids.present?
      completion_message = ""

      if (result.status == :failed)
        # This is the best format, unfortunately it has bash console color codes embedded in it.
        completion_message = notification.fully_formatted(1)
        # need to remove those color codes from the string
        completion_message.gsub!(/\[(\d)+m/, '')
      end

      Array(testrail_ids).each do |id|
        tc = @test_case_hash[id.to_i]
        next unless tc # A test case ID exists in the rspec file, but not on testrail
        tc.set_status(result.status, completion_message)
        @@cases << tc
        @executed_test_ids << id.to_i
      end

      # Batches together test cases before posting. Relies on environment variable TESTRAIL_BATCH_SIZE to determine
      # batch size.
      # Relies on an 'after suite' hook to capture and post results for any number of remaining test cases less
      # than the batch size
      if @@cases.size >= @batch_size.to_i
        TestRailPlanFormatter.post_results @@cases
        @@cases.clear
      end
    end

    # test_cases is an array of TestCase instances
    def self.post_results(test_cases)
      data = []

      test_cases.each do |tc|

        status_value = TestRailOperations.status_rspec_to_testrail(tc.status)
        if status_value == TestRailOperations::UNTESTED
          # ! SUPER IMPORTANT !
          # test rail does NOT allow you to set the status of a test to untested.
          # so skip them
          next
        end

        # id was not found in the list of test run id's. Due to incorrect include pattern in rspec.
        next unless tc.temp_id

        data << {
            "test_id" => tc.temp_id, # results require the new test case temporary ID's, not the static ID's
            "status_id" => status_value,
            "comment" => tc.result_message
        }
      end

      if data.size > 0
        TestRailOperations.post_run_results(@@run_id, data)
        test_case_ids = test_cases.collect { |tc| tc.id }
        puts "Successfully posted results for testcases: #{test_case_ids} to test run: #{@@run_id}"
      else
        puts "No results sent to test rail"
      end
    end

    alias_method :example_passed, :example_finished
    alias_method :example_pending, :example_finished
    alias_method :example_failed, :example_finished

    private

    # For pushing results up to a test plan in TestRail.
    def is_for_test_rail_plan
      !ENV["TESTRAIL_RUN"].nil? && !ENV["TESTRAIL_PLAN_ID"].nil? && !ENV["TESTRAIL_ENTRY_ID"].nil? && !ENV["TESTRAIL_ENTRY_RUN_ID"].nil?
    end

    # For pushing results to a single, existing test run in TestRail
    def is_for_test_rail_run
      !ENV["TESTRAIL_RUN_ID"].nil? && ENV["TESTRAIL_RUN"].nil? && ENV["TESTRAIL_PLAN_ID"].nil?
    end
  end

  def self.get_total_count
    @@total_count
  end

  def self.get_skip_count
    @@skip_count
  end

  def self.get_run_count
    @@run_count
  end

  # Adds a documentation formatter to the rspec if one is not there already.
  def self.add_formatter_for(config)
    # For some reason, adding a custom formatter will remove any other formatters.
    # Thus during execution nothing gets printed to the screen. Need to add another
    # formatter to indicate some sort of progress
    found_doc_formatter = false
    config.formatters.each do |fm|
      if (fm.class == RSpec::Core::Formatters::DocumentationFormatter)
        found_doc_formatter = true
        break
      end
    end
    unless found_doc_formatter
      config.add_formatter "doc"
    end
  end

  # Takes care of filtering out tests that are NOT assigned to the user. So essentially runs only
  # tests specified in a testrun in testrail, and that are assigned to a particular user.
  # \config - The Rspec configuration
  # \user_id - An integer ID corresponding to the testrail user
  # \test_run_cases - A hash of TestCase instances
  def self.filter_rspecs_by_test_run_and_user(config, user_id, test_run_cases)
    config.filter_run_including testrail_id: lambda { |value|
      # The test id's are strings. Convert them to integers to make comparison easier
      test_ids = value.collect { |str| str.to_i }
      # Compute the intersection using the handy &() method
      intersect = test_run_cases.keys & test_ids
      assigned_to_ids = []
      # Do include if the intersection contains a test id
      if intersect.size > 0
        test_ids.each do |id|
          test_case = test_run_cases[id]
          if test_case.nil?
            next
          end
          assigned_to_ids << test_case.assigned_to
        end
        # return true to execute the test if any one of the testcase ID's is assigned to the user
        do_execute = assigned_to_ids.include? user_id
        if do_execute
          puts "Assigned to user. Including testcase ID's: #{value}"
        else
          puts "Not assigned to user: Skipping #{value}"
        end
        do_execute
      else
        false
      end
    }
  end

  # Filters an rspec run by testrail_id's for bridge
  # Filters an rspec run by testcases found in a particular testrun on testrail.
  def self.filter_rspecs_by_test_run(config, test_run_cases)
    # This lambda gets called once for each example
    # Here value is an array of string test case ID's.
    config.filter_run_including testrail_id: lambda { |value|
      @@total_count += 1
      unless value.is_a? Array
        @@skip_count += 1
        puts "ERROR! testcase has invalid testrail ID: #{value}. Value should be an array, got: #{value.class}".red
        return false
      end
      # The test id's are strings. Convert them to integers to make comparison easier
      test_ids = value.collect { |str| str.to_i }
      # Compute the intersection using the handy &() method
      intersect = test_run_cases.keys & test_ids
      # Do not include if the test cases have already been run and have ALL passed.
      # (That would be a waste of time to rerun test's that have already passed)
      pass_count = 0
      skip_count = 0
      # Do include if the intersection contains a test id
      if intersect.size > 0
        test_ids.each do |id|
          test_case = test_run_cases[id]
          if test_case.nil?
            next
          end
          # puts "   #{id} temp id: #{test_case.temp_id} Status: #{test_case.status}, "
          pass_count += 1 if test_case.status == :passed
          skip_count += 1 if test_case.status == :pending
        end
        all_passed = pass_count == test_ids.count
        all_skipped = skip_count == test_ids.count
        if all_passed
          @@skip_count += 1
          puts "Skipping test case #{value}, because all tests already passed"
        end
        if all_skipped
          @@skip_count += 1
          puts "Skipping test case #{value}, because all tests marked pending"
        end
        do_execute = (pass_count + skip_count) != test_ids.count
        @@run_count += 1 if do_execute
        do_execute
      else
        @@skip_count += 1
        false
      end
    }
  end

  # Filters an rspec run by test_id's for canvas.
  # This is used for filtering out test cases that have already been run previously, say on a previous
  # test run that was aborted early and restarted.
  # In this case we skip tests that already passed or were marked as pending (rspec for skipped)
  def self.filter_rspecs_by_testid(config, test_run_cases)
    # This lambda gets called once for each example
    # Here value is an array of string test case ID's.
    config.filter_run_including test_id: lambda { |id|
      @@total_count += 1
      id = id.to_i
      # The test id's are integers, and in canvas there is only one ID per test case, NOT an array like Bridge
      in_run = test_run_cases.keys.include?( id )

      # Do include if the intersection contains a test id
      if in_run
        test_case = test_run_cases[id]

        if (test_case.status == :passed)
          @@skip_count += 1
          puts "Skipping test case #{id}, because it has already passed"
          return false
        end

        if (test_case.status == :pending)
          @@skip_count += 1
          puts "Skipping test case #{id}, because it is marked pending"
          return false
        end

        @@run_count += 1
        return true # do execute this test
      else
        @@skip_count += 1
	puts "Skipping test case #{id}, because it was not in test_run_cases"
        return false
      end
    }
  end

  # The param is an RSPEC config
  # The second param is a symbol for which product to hook into
  def self.register_rspec_integration(config, product, add_formatter: true)
    # Runs test cases as found in a test run on testrail

    # This will select test examples to run based off of what test rail defines, not what
    # the file pattern on the command line defines.
    # That is, this will take a test run (int test rail), and run all the cases defined in it.

    # First clear any filters passed in from the command line
    config.inclusion_filter = nil
    test_run_cases = TestRailOperations.get_test_run_cases(ENV["TESTRAIL_RUN_ID"].to_i)

    user_id = nil
    unless ENV["TESTRAIL_ASSIGNED_TO"].nil?
      user_json = TestRailOperations.get_test_rail_user_by_email(ENV["TESTRAIL_ASSIGNED_TO"])
      user_id = user_json["id"]
      puts "Testrail assigned to: #{user_json}"
    end

    if user_id
      TestRailRSpecIntegration.filter_rspecs_by_test_run_and_user(config, user_id, test_run_cases)
    else
      case(product)
      when :bridge
        TestRailRSpecIntegration.filter_rspecs_by_test_run(config, test_run_cases)
      when :canvas
        TestRailRSpecIntegration.filter_rspecs_by_testid(config, test_run_cases)
      end
    end

    config.add_formatter TestRailRSpecIntegration::TestRailPlanFormatter
    TestRailRSpecIntegration::TestRailPlanFormatter.set_product(product)
    if add_formatter
      TestRailRSpecIntegration.add_formatter_for(config)
    end

    # Captures and posts results for any remaining test case results in @@cases that don't fill a full batch
    config.after(:suite) do |suite|
      total_cases = TestRailPlanFormatter.class_variable_get(:@@cases)

      if total_cases.size > 0
        TestRailRSpecIntegration::TestRailPlanFormatter.post_results total_cases
      end
    end
  end

  # Registers a callback custom formatter to an rspec. The new test run is created from
  # the results of the tests. This is in effect the opposite of the method above
  # (register_rspec_integration).
  def self.add_rspec_callback(config, product, add_formatter: true)
    config.add_formatter TestRailRSpecIntegration::TestRailPlanFormatter
    TestRailRSpecIntegration::TestRailPlanFormatter.set_product(product)
    if add_formatter
      TestRailRSpecIntegration.add_formatter_for(config)
    end
  end
end
