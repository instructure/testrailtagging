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

      # Please note that the API is rate limited on TestRail Hosted and may throttle requests.
      # TestRail might also return a 429 Too Many Requests response which you are expected to handle.
      # Such a response also includes a Retry-After header indicating how many seconds to wait
      # before you are allowed to submit the next request.
      # http://docs.gurock.com/testrail-api2/introduction #Rate Limit
      response = nil
      # todo: use header [Retry-After] secs
      # for HTTPTooManyRequests 429 error, retry post after either 10s, 30s, 90s or 270s.
      exponential_backoff_seconds = 10

      4.times do
        begin
          response = send_post(uri, data)
          break
        rescue TestRail::APIError => e
          if e.message && e.message.match("HTTP 500.*Deadlock")
            sleep 1
          elsif e.message && e.message.match("HTTP 429")
            puts "TestRail rate limited. retrying in #{exponential_backoff_seconds}"
            sleep exponential_backoff_seconds
            exponential_backoff_seconds *= 3
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
