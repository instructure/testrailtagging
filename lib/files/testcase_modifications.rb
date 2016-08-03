require_relative "testrail_operations"
require_relative "RSpecParser"

# =================================================================================
#
# Test case parsing and modifications
#
# =================================================================================

module TestCaseModifications
  # Given a line of code extracted from an RSPEC example, it returns an array of numbers (integers)
  # that correspond to the testrail_id's.
  def self.get_example_testrail_ids(line)
    # puts line
    testrail_id = "testrail_id:"
    length = testrail_id.size
    index = line.index(testrail_id)

    substr = line[(index + length)..-1]
    comma = substr.index(",")

    if comma
      substr = substr[0, comma]
    end
    substr = substr.gsub(" do", "")
    substr = substr.gsub("%w[", "")
    substr = substr.gsub("]", "")

    numbers = substr.split(" ")
    result = []
    numbers.each do |str|
      result << str.to_i
    end
    result
  end

  # Gets a description of the minimum screen size given a line of text from the rspec.
  # Given a line of code that was extracted from the test case contains a testrail_id tag,
  # this function will extract the test rail ID, look it up in a list of test cases
  # and return the type of screen size this minimally works on.
  def self.get_example_device_type(line, test_cases)
    ids = get_example_testrail_ids(line)
    # puts ids
    if (ids.size == 1)
      id = ids[0]
      tc = test_cases[id]
      if tc
        tc.screen_size
      else
        # It could be in some other test rail project
        nil
      end
    else
      # Multiple test rail id's specified for the example.
      desktop_count = 0
      tablet_count = 0
      phone_count = 0
      ids.each do |id|
        tc = test_cases[id]
        next if tc.nil?

        case tc.screen_size
          when "Desktop"
            desktop_count += 1
          when "Tablet"
            tablet_count += 1
          when "Phone"
            phone_count += 1
        end
      end
      # Always go with the smallest minimum size specified in the test rail id list
      if phone_count != 0
        "Phone"
      elsif tablet_count != 0
        "Tablet"
      elsif desktop_count != 0
        "Desktop"
      else
        "<-- ========================== ERROR ============================== -->"
      end
    end
  end

  # Finds the lowest priority for an array of test cases
  # ids - array of test cases integer ID's.
  # test_cases - array of TestCase instances
  # returns the lower priority for a given set of test cases
  def self.lowest_priority_of(ids, test_cases)
    p0_count = 0
    p1_count = 0
    p2_count = 0
    p3_count = 0
    ids.each do |id|
      tc = test_cases[id]
      next if tc.nil?

      case tc.priority
        when 0
          p0_count += 1
        when 1
          p1_count += 1
        when 2
          p2_count += 1
        when 3
          p3_count += 1
      end
    end

    # Always go with the lowest priority specified in the test rail id list
    if p0_count != 0
      0
    elsif p1_count != 0
      1
    elsif p2_count != 0
      2
    elsif p3_count != 0
      3
    else
      "<-- ========================== ERROR ============================== -->"
    end
  end

  # Get the priority of the test case given a line of text from the rspec.
  # Given something like this:
  # example "I make a course", testrail_id: %w[123456], priority: 1 do
  # it will return a numeric value of the test priority
  def self.get_example_priority(line, test_cases)
    ids = get_example_testrail_ids(line)
    if (ids.size == 1)
      id = ids[0]
      tc = test_cases[id]
      if tc
        tc.priority
      else
        # It could be in some other test rail project
        nil
      end
    else
      # Multiple test rail id's specified for the example.
      lowest_priority_of(ids, test_cases)
    end
  end

  # PreCondition: This is only called on examples that are verified to have test id's attached to them.
  # Removes and adds in a tag to the string string parameter 'line'.
  def self.add_tag(tag, line, type_string, prepend_colon:true)
    tag_index = line.index(tag)
    modified_line = "0xDEADBEAF"
    if tag_index
      # Found an existing tag:, remove the existing one first.
      next_comma = line.index(",", tag_index)
      if next_comma
        modified_line = line[0, tag_index - 2] + line[next_comma..-1]
      else
        # It's at the end, Look for the 'do' keyword
        last_do = line.index("do\n")
        first_part = line[0, tag_index - 2]
        second_part = line[last_do..-1]
        modified_line = first_part + " " + second_part
      end
      line = modified_line
    end

    colon = ":" if prepend_colon

    tag_index = line.index(tag)
    unless tag_index
      # None found, add one after testrail_id:
      testrail_index = line.index("testrail_id:")
      if testrail_index
        next_comma = line.index(",", testrail_index)
        if next_comma
          modified_line = line.insert(next_comma, ", #{tag} #{colon}#{type_string.downcase}")
        else
          # It was at the end already.
          last_bracket = line.index("]", testrail_index)
          modified_line = line.insert(last_bracket + 1, ", #{tag} #{colon}#{type_string.downcase}")
        end
      end
    end
    modified_line
  end

  # Modifies the Rspec files to add metadata to each test example block.
  # This will pull down data from testrail.com for each test case. It will then extract the priority
  # and the desktop size that the test case can run on, and then add those as metadata to the
  # example. This will modify all the rspec files in the regression_spec folder.
  def self.add_tags_to_rspec_tests(tag_priority: true, tag_device: true)
    test_cases = TestRailOperations.get_test_rail_cases
    spec_files = Dir["regression_spec/**/*_spec.rb"]
    spec_files.each do |file|
      puts "Rspec file: #{file}"
      changes = [] # The new lines of code for the file
      # Read the file
      File.open(file).each do |line|
        new_line = line

        if line.match("testrail_id")
          if tag_device
            type = get_example_device_type(line, test_cases)
            if type
              new_line = add_tag("device:", line, type)
            end
          end

          if tag_priority
            priority = get_example_priority(line, test_cases)
            if priority
              new_line = add_tag("priority:", new_line, priority.to_s, prepend_colon: false)
            end
          end
        end
        changes << new_line
      end

      # Write the file out
      File.open(file, "w") do |f|
        changes.each do |line|
          f.puts line
        end
      end
    end
  end

  # This takes the file name associated with each testrail_id and posts it to the associated test rail ID on
  # testrail.com.
  # For example, if an rspec test example has a testrail_id of 123123 in file foo_spec.rb, it will update the test
  # case on test rail and update the spec location field with foo_spec.rb.
  # This will iterate over all the files in the regression_spec folder.
  def self.update_automated_status(suite_ids, dryrun:false)
    test_cases = TestRailOperations.get_test_rail_cases_for_all_suites(suite_ids)
    regression_files = Dir["regression_spec/**/*_spec.rb"]
    spec_files = regression_files + Dir["spec/**/*_spec.rb"]
    # For keeping test cases that actually changed
    changed_cases = {}
    orphaned_ids_count = 0
    # parse all the files looking for examples
    spec_files.each do |file|
      # puts "Rspec file: #{file}"
      File.open(file).each do |line|
        if line.match("testrail_id")
          testrail_ids = get_example_testrail_ids(line)
          testrail_ids.each do |id|
            # puts "      id: #{id}"
            tc = test_cases[id]
            if tc
              if file != tc.file
                puts "\r\nID: #{id} - #{tc.title[0,20]}"
                puts "  Old File: #{tc.file}"
                puts "  New File: #{file}"
                tc.file = file
                changed_cases[id] = tc
              end

              # assuming it never becomes un-automated
              unless tc.automated
                puts "  ID: #{id}  Marking automated"
                tc.automated = true
                changed_cases[id] = tc
              end
            else
              puts "Test CaseID: #{id} not found in any testrail suite for project: #{TestRailOperations.project_id}"
              orphaned_ids_count += 1
            end
          end
        end
      end
    end

    puts "\nTest Cases that will get modified" if changed_cases.count > 0
    trclient = TestRailOperations.get_test_rail_client
    changed_cases.each do |id_key, tc_val|
      puts "Test Case: id: #{id_key}, #{tc_val.file}" if tc_val.file
      url = "update_case/#{id_key}"
      data = { "custom_spec_location" => tc_val.file, "custom_automated" => tc_val.automated }
      unless dryrun
        trclient.send_post_retry(url, data)
      end
    end
    puts "Number of orphaned testcase IDs: #{orphaned_ids_count}"
  end

  # checks for duplicate test case ID's in the rspec tests
  def self.check_duplicates
    regression_files = Dir["regression_spec/**/*_spec.rb"]
    spec_files = regression_files + Dir["spec/**/*_spec.rb"]
    # For keeping a running list of found ID's
    # Key is integer ID
    # Value is the file
    ids = {}
    # parse all the files looking for examples
    spec_files.each do |file|
      # puts "Rspec file: #{file}"
      File.open(file).each do |line|
        if line.match("testrail_id")
          testrail_ids = get_example_testrail_ids(line)
          testrail_ids.each do |id|
            # puts "      id: #{id}"
            if ids[id]
              puts "Found duplicate: #{id}"
              puts "Other File: #{ids[id]}"
              puts "This  File: #{file}"
            else
              ids[id] = file
            end
          end
        end
      end
    end
  end

  # Parses the rspec files and reports how many test cases are skipped, and a percentage of
  # the test cases that are executed.
  # returns a hash of test cases, where
  # the key is an integer of the test case ID (as found in test rail), and
  # the value  is an instance of TestCase, containing all the skip information and everything.
  def self.parse_specs

    rspec_examples = []
    spec_files = Dir["regression_spec/**/*_spec.rb"]
    example_count = 0
    skip_count = 0
    file_count = 0
    # parse all the files looking for examples
    spec_files.each do |file|
      file_count += 1
      parser = RSpecParser.new(file)
      parser.parse
      parser.test_cases.each do |tc|
        tc.file = file
        if tc.skip.count > 0
          skip_count += 1
        end
      end
      rspec_examples += parser.test_cases
      # puts "%5d in %s" % [parser.test_cases.count, file]
      example_count += parser.test_cases.count
    end
    puts "total files: #{file_count}"
    puts "total examples: #{example_count}"
    puts "total examples skipped: #{skip_count}"
    puts "total executed: #{example_count - skip_count}"
    puts "total coverage: %.2f %" % [(1.0 - (skip_count / example_count.to_f)) * 100]

    result = {}
    rspec_examples.each do |tc|
      next if tc.id.nil?
      tc.id.each do |id|
        result[id.to_i] = tc
      end
    end
    result
  end

  @browsers = { "none" => 0, "chrome" => 1, "firefox" => 2, "ie10" => 3, "ie11" => 4, "safari" => 5 }
  def self.browsers_to_testrail(browser_array)
    result = []
    browser_array.each do |name|
      if name == "allbrowsers"
        result = [1, 2, 3, 5]
        return result
      else
        result << @browsers[name]
      end
    end
    result
  end

  # Parses all the test cases as found in the rspec files.
  # then pushes information about teach test case up to testrail.
  # This will update 3 fields about each test case:
  # 1. the spec file location
  # 2. if the test is skipped, and on which browser
  # 3. if the test is automated (by default is true)
  def self.push_to_testrail
    rspec_examples = parse_specs
    trclient = TestRailOperations.get_test_rail_client

    # First set the fields to blank in test rail
    test_cases = TestRailOperations.get_test_rail_cases
    # test_cases.each do |key_id, val_tc|
    #  url = "update_case/#{key_id}"
    #  data = { "custom_spec_location" => nil, "custom_browser_skip" => [], "custom_automated" => false }
    #  trclient.send_post(url, data)
    # end

    # Then upload the information contain in our rspec files
    rspec_examples.each do |id_key, tc_val|
      if test_cases.key?(id_key)
        url = "update_case/#{id_key}"
        puts "updating test case: "
        browser_skips = browsers_to_testrail(tc_val.skip)
        data = { "custom_spec_location" => tc_val.file, "custom_browser_skip" => browser_skips, "custom_automated" => true }
        trclient.send_post_retry(url, data)
      end
    end
  end
end
