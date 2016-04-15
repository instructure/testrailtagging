require_relative "testrail_operations"

# =================================================================================
#
# Test case printing and inspections
#
# =================================================================================

module TestRailQueries
  # Prints to the console, the test cases sorted by priority (ascending).
  def self.print_priority_sorted_test_cases
    test_cases = TestRailOperations.get_test_rail_cases
    sorted_cases = test_cases.values.sort_by do |tc|
      tc.priority
    end

    automated_count = 0
    sorted_cases.each do |tc|
      tc.print
      automated_count += 1 if tc.automated
    end

    puts "Number Test Cases: #{test_cases.size}"
    puts "Number Test Cases Automated: #{automated_count}"
    percentage = (automated_count / test_cases.size.to_f) * 100.0
    puts "Percentage Automated #{percentage.round(1)}%"
  end

  # Prints to the console, the test cases that work on phone devices. (Sorted by test ID)
  def self.print_phone_test_cases
    test_cases = TestRailOperations.get_test_rail_cases

    phones = []
    test_cases.values.each do |tc|
      phones << tc if tc.screen_size == "Phone"
    end

    sorted_ids = phones.each do |tc|
      tc.id
    end

    sorted_ids.each do |tc|
      tc.print
    end

    puts "Number Test Cases: #{test_cases.size}"
    puts "Number Test Cases Phone: #{phones.size}"
    percentage = (phones.size / test_cases.size.to_f) * 100.0
    puts "Percentage Phone #{percentage.round(1)}%"
  end

  # Prints to the console, all the test case ID's and the minimum screen size they work on
  def self.print_test_case_devices
    test_cases = TestRailOperations.get_test_rail_cases

    test_cases.each do |key, value|
      puts "ID: #{key}, #{value.screen_size}"
    end
  end

  # Prints to the console, all the test runs
  def self.print_all_test_runs
    test_runs = TestRailOperations.get_test_rail_runs
    count_runs  = 0
    count_open  = 0
    count_close = 0
    test_runs.each do |test_run|
      puts "Run: #{test_run["name"]}, id: #{test_run["id"]} complete: #{test_run["is_completed"]} "
      if test_run["is_completed"]
        count_close += 1
      else
        count_open += 1
      end

      count_runs += 1
    end
    puts "========================================"
    puts "Total Test Runs: #{count_runs}"
    puts "Total Open: #{count_open}"
    puts "Total Closed: #{count_close}"
  end

  # Prints to the console all the test plans in bridge
  def self.print_all_test_plans
    test_plans = TestRailOperations.get_test_rail_plans
    count_plans = 0
    test_plans.each do |plan|
      id = plan["id"]
      puts "Plan: ID: #{id}, #{plan["name"]}"
      count_plans += 1
      pjson = TestRailOperations.get_test_rail_plan(id)
      puts "    passed: #{pjson["passed_count"]}, failed: #{pjson["failed_count"]}, retest: #{pjson["retest_count"]}, blocked: #{pjson["blocked_count"]}"
      puts "    entries count: #{pjson["entries"].count}"
      pjson["entries"].each do |entry|
        puts "    entry: #{entry["id"]} - #{entry["name"]}"
      end
    end
    puts "========================================"
    puts "Total Test Plans: #{count_plans}"
  end

  def self.print_all_users
    users = TestRailOperations.get_test_rail_users
    users.each do |user|
      puts user
    end
  end
end
