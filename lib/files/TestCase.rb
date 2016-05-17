
module TestRailOperations
  # Represents a test case in test rail.
  class TestCase
    attr_accessor :id, :title, :priority, :automated, :screen_size, :result_message, :status
    attr_accessor :automatable, :references
    attr_accessor :file # Which rspec file the test case is found in
    attr_accessor :metadata, :skip
    attr_accessor :temp_id
    attr_accessor :assigned_to

    def initialize(id, title, priority, automated, screen_size, automatable, references)
      @id          = id
      @title       = title
      @priority    = priority
      @automated   = automated
      @screen_size = screen_size
      @automatable = automatable
      @references  = references
      @skip = []
    end

    def set_status(status, message)
      @status = status
      @result_message = message # a string
    end

    def print
      puts ""
      puts "Test Case: #{@id}, #{@title}"
      puts "\tPriority:    #{@priority}"
      puts "\tScreen Size: #{@screen_size}"
      puts "\tAutomated:   #{@automated}"
      puts "\tSkips:       #{skip}"
    end
  end
end
