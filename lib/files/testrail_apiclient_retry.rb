require "testrail_client"

# =================================================================================
#
# API's for Test Rail
#
# =================================================================================

module TestRail
  class APIClient
    def send_post_retry(uri, data)
      # Gurock api's often deadlocks with errors like this:
      #   TestRail API returned HTTP 500 ("Deadlock found when trying to get lock; try restarting transaction")
      # So if they say to retry, then that's what we will do
      response = nil
      3.times do
        begin
          response = send_post(uri, data)
          break
        rescue TestRail::APIError => e
          if e.message && e.message.match("HTTP 500.*Deadlock")
            sleep 1
          else
            # Don't retry it, let the exception propagate
            raise
          end
        end
      end
      response
    end
  end
end
