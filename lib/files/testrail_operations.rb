require_relative "testrail_apiclient_retry"
require_relative "TestCase"

# =================================================================================
#
# API's for Test Rail
#
# =================================================================================

module TestRailOperations
  def self.set_testrail_ids(pid, sid)
    @@testrail_project_id = pid
    @@testrail_suite_id = sid
  end

  def self.project_id
    @@testrail_project_id
  end

  def self.suite_id
    @@testrail_suite_id
  end

  # Splits a string by a command and returns an array.
  def self.split_by_comma(device_string)
    splits = device_string.split(",")
    key = splits[0].chomp
    val = splits[1].lstrip
    [key, val]
  end

  # Gets the Test Rail client
  # http://docs.gurock.com/testrail-api2/bindings-ruby
  def self.get_test_rail_client
    url = "https://canvas.testrail.com"
    trclient = TestRail::APIClient.new(url)
    trclient.user = ENV["TESTRAIL_USER"]
    trclient.password = ENV["TESTRAIL_PASSWORD"]
    trclient
  end

  # Gets the definition of device types that are assigned to our test rail cases.
  # It looks like this:
  # {1=>"Desktop", 2=>"Tablet", 3=>"Phone"}
  def self.get_test_rail_screen_size_codes
    trclient = get_test_rail_client
    case_fields = trclient.send_get("get_case_fields")

    results = {}
    case_fields.each do |case_field|
      if (case_field["name"] == "screen_size")
        config_array = case_field["configs"] # The array usually has a size of 1, but sometimes 0
        if config_array.size > 0
          config = config_array[0]
          # Some configs have items, like screen size
          items = config["options"]["items"]
          if items
            devices = items.split("\n")
            devices.each do |device|
              key, value = split_by_comma(device)
              results[key.to_i] = value
            end
          end
        end
      end
    end
    results
  end

  # Gets the definition of the priority codes that are assigned to our test rail cases.
  # The priority codes on testrail do not match our nice 1,2,3 numbers. Their codes are
  # different from ours. i.e.
  #
  # {1=>"3 - Low Priority", 3=>"2 - Test If Time", 4=>"1 - Must Test", 6=>"Smoke Test"}
  #
  # Therefore this function creates a more bridge friendly translation.
  def self.get_test_rail_priority_codes
    trclient = get_test_rail_client
    # retreive priority information
    # http://docs.gurock.com/testrail-api2/reference-priorities
    priority_response = trclient.send_get("get_priorities")

    results = {}
    priority_response.each do |priority|
      # find the numeric priority
      name = priority["name"]
      splits = name.split("-")
      key = priority["id"].to_i
      if splits.size == 2 && splits[0].to_i
        val = { name: name, user_friendly_priority: splits[0].to_i }
        results[key] = val
      elsif name == "Smoke Test"
        val = { name: "Smoke", user_friendly_priority: 0 }
        results[key] = val
      elsif name == "STUB"
        val = { name: "Stub", user_friendly_priority: 7 }
        results[key] = val
      end
    end
    results
  end

  # Gets a hash of TestCase instances.
  # The keys are the numeric(integer) test rail case ID's.
  # The Values are the instance of TestCase.
  # Each TestCase instance corresponds to a test case in test rail.
  # param - project. The integer ID of the project
  # param - test_suite. The integer ID of the test suite.
  # return - A hash of TestCase instances
  def self.get_test_rail_cases
    trclient        = get_test_rail_client
    screen_sizes    = get_test_rail_screen_size_codes
    priorities      = get_test_rail_priority_codes
    test_cases      = {}

    binding.pry
    puts "Testrail Project ID: #{self.project_id}"
    puts "Testrail Suite   ID: #{self.suite_id}"
    # retrieve test cases
    testcases_url = "get_cases/#{self.project_id}&suite_id=#{self.suite_id}"
    response = trclient.send_get(testcases_url)
    response.each do |test_case|
      id = test_case["id"]
      size = test_case["custom_screen_size"]
      screen_size_description = screen_sizes[size]
      priority = test_case["priority_id"]
      priority_description = priorities[priority]
      if priority_description
        priority_code = priority_description[:user_friendly_priority]
        automated = test_case["custom_automated"]
        tc = TestCase.new(id.to_s, test_case["title"], priority_code, automated, screen_size_description)
        tc.file = test_case["custom_spec_location"]
        test_cases[id] = tc
      end
    end

    test_cases
  end

  # Gets JSON data about the test runs on testrail for the given project and suite
  def self.get_test_rail_runs
    trclient = get_test_rail_client
    request  = "get_runs/#{self.project_id}"
    trclient.send_get(request)
  end

  # Returns a list of test plans for a project.
  # http://docs.gurock.com/testrail-api2/reference-plans#get_plans
  def self.get_test_rail_plans
    trclient = get_test_rail_client
    request  = "get_plans/#{self.project_id}"
    trclient.send_get(request)
  end

  # Gets JSON data about an existing test plan
  # http://docs.gurock.com/testrail-api2/reference-plans#get_plan
  def self.get_test_rail_plan(plan_id)
    trclient = get_test_rail_client
    request  = "get_plan/#{plan_id}"
    trclient.send_get(request)
  end

  # Adds one test run to a test plan
  # Returns hash containing:
  # 1. The test run ID of the test run.
  # 2. The entry ID of the test run which is a large Guid like this:
  # "id"=>"638fd46c-7c3e-4818-9c90-f411a2dec52a"
  def self.create_test_plan_entry(plan_id, name, include_all_cases: true, case_ids: [])
    if !include_all_cases && case_ids.count == 0
      return "Error! Must create a test plan with at least one test case"
    end

    request = "add_plan_entry/#{plan_id}"
    data = {
        "suite_id" => self.suite_id,
        "name" => name,
        "include_all" => include_all_cases,
        "case_ids" => case_ids
    }

    trclient = get_test_rail_client
    response = trclient.send_post_retry(request, data)
    { entry_id: response["id"], run_id: response["runs"][0]["id"] }
  end

  # Updates a test plan with the given entry_id and array of test case IDSs
  def self.add_test_case_to_test_plan(plan_id, entry_id, case_ids)
    request = "update_plan_entry/#{plan_id}/#{entry_id}"
    data = {
        "suite_id" => self.suite_id,
        "case_ids" => case_ids
    }

    trclient = get_test_rail_client
    trclient.send_post_retry(request, data)
  end

  def self.keep_only(plan_id, entry_id, case_ids)
    request = "update_plan_entry/#{plan_id}/#{entry_id}"
    data = {
        "suite_id" => self.suite_id,
        "include_all" => false,
        "case_ids" => case_ids
    }

    trclient = get_test_rail_client
    trclient.send_post_retry(request, data)
  end

  # Creates a test run on testrail
  # param project_ID - The integer identifier of the project on test rail.
  # param suite_id   - The integer identifier of the test suite on test rail.
  # param name       - The string name to call the new test run
  # param test_case_ids - The array of numerical integers of test cases to add to the test run
  # returns - The number ID of the test run.
  def self.create_test_run(project_id, suite_id, name, test_case_ids)
    request = "add_run/#{project_id}"
    data = {
      "suite_id" => suite_id,
      "name" => name,
      "include_all" => false,
      "case_ids" =>  test_case_ids
    }

    trclient = get_test_rail_client
    response = trclient.send_post_retry(request, data)
    response["id"]
  end

  def self.add_testcase_to_test_run(test_run_id, case_ids)
    request = "update_run/#{test_run_id}"
    data = { "case_ids" => case_ids }
    trclient = get_test_rail_client
    trclient.send_post_retry(request, data)
  end

  PASSED = 1
  BLOCKED = 2
  UNTESTED = 3
  RETEST = 4
  FAILED = 5
  PENDING = 6
  @rspec_to_testrail_status_map = {
    passed: PASSED, blocked: BLOCKED, untested: UNTESTED, retest: RETEST, failed: FAILED, pending: PENDING
  }
  # Converts an rspec test result (a symbol) to an integer that TestRail understands.
  def self.status_rspec_to_testrail(result_symbol)
    @rspec_to_testrail_status_map[result_symbol]
  end

  # Converts the a TestRail integer result status into a symbol (that rspec uses) that is human readable
  def self.status_testrail_to_rspec(int_id)
    @rspec_to_testrail_status_map.key(int_id)
  end

  # Sends test result data back to testrail to update cases in a test run
  # param run_id - integer value designating the test run to update
  # param data   - A hash containing an array of hashes with test results
  def self.post_run_results(run_id, data)
    trclient = get_test_rail_client
    uri = "add_results/#{run_id}"
    trclient.send_post_retry(uri, "results" => data)
  end

  # When a test run is created, the test cases have new, sort of temporary ID's.
  # These are completely different from the permanent static ID's of the test cases.
  # Given a test run ID, this gets the test cases that are assigned to that test run.
  # It returns a hash where the key is the integer permanent ID, and the value is a TestCase instance.
  def self.get_test_run_cases(run_id)
    result = {}
    trclient = get_test_rail_client
    response = trclient.send_get("get_tests/#{run_id}")
    response.each do |r|
      # Each response hash for a test case in a run looks like this:
      #
      # {"id"=>481664, "case_id"=>152222, "status_id"=>5, "assignedto_id"=>49, "run_id"=>2641,
      # "title"=>"The my Learning page has all my courses listed. Overdue, Next Up, Optional,
      # Completed", "type_id"=>2, "priority_id"=>3, "estimate"=>nil, "estimate_forecast"=>nil,
      # "refs"=>nil, "milestone_id"=>nil, "custom_sprint_date"=>nil, "custom_commit_url"=>nil,
      # "custom_reviewed"=>false, "custom_automated"=>true,
      # "custom_spec_location"=>"regression_spec/learner_management/mylearning_spec.rb",
      # "custom_test_order"=>nil, "custom_screen_size"=>3, "custom_preconds"=>nil,
      # "custom_steps_separated"=>nil, "custom_browser_skip"=>[]}
      #

      permanent_id = r["case_id"].to_i
      tc = TestCase.new(permanent_id, r["title"], r["priority_id"].to_i, r["custom_automated"], r["custom_screen_size"].to_i)
      tc.temp_id = r["id"].to_i
      tc.assigned_to = r["assignedto_id"].to_i
      tc.set_status(status_testrail_to_rspec(r["status_id"].to_i), nil)

      value = tc
      key = permanent_id
      result[key] = value
    end
    result
  end

  # Gets the string name of the test run, given the test run id as an integer
  # if the test id is not found, it returns an empty string
  def self.get_test_run_name(run_id)
    runs = get_test_rail_runs(self.project_id)
    runs.each do |run|
      if run_id == run["id"].to_i
        return run["name"]
      end
    end
    ""
  end

  def self.get_test_rail_users
    # Returns an array of user hashes. Like this:
    # [
    # {
    #    "email": "alexis@example.com",
    #    "id": 1,
    #    "is_active": true,
    #    "name": "Alexis Gonzalez"
    # },
    # ....
    # ]
    get_test_rail_client.send_get("get_users")
  end

  # Given an email address, gets the user json data
  def self.get_test_rail_user_by_email(email)
    # The response looks like this:
    # {
    #    "email": "alexis@example.com",
    #    "id": 1,
    #    "is_active": true,
    #    "name": "Alexis Gonzalez"
    # }
    get_test_rail_client.send_get("get_user_by_email&email=#{email}")
  end
end
