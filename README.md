# Testrailtagging

Testrailtagging is some ruby modules and classes that integrate rspec together with GuRock's Testrail web-application.
The main feature of this gem is to allow realtime reporting of rspec results to testrail.

There is also functionality to push and pull data to testrail.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'testrailtagging'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install testrailtagging

## Configuration

First, you must have a valid and active testrail account you want to post results to.
Second to use the API's you will need a username and a password for testrail.

Hence to do anything with this gem you will need to set the following environment variables:

`TESTRAIL_USER`
`TESTRAIL_PASSWORD`
`TESTRAIL_URL` (example:"https://canvas.testrail.com")

which this gem will look for and use.

`TESTRAIL_RUN_DELETE_DAYS`
`TESTRAIL_RUN_DELETE_FORCE`
With RUN_DELETE_DAYS defined the gem will delete all test runs in the provided plan_id that are older than
the days specified.  There is a limit of 7 days which can be overridden with RUN_DELETE_FORCE set to true.

### For Reporting results to testrail

This is for reporting rspec results to a pre-existing test run at testrail.com.
#### Testrail Id
In testrail find the ID of the test run you want to push results to. You can find it in URL like this:

`https://blablabla.testrail.com/index.php?/runs/view/14153`

Here the test run is 14153.

Then you set an environment variable called TESTRAIL_RUN_ID, with that value. For example:

`export TESTRAIL_RUN_ID=14153`

#### Batching Results (optional)
You can also set an optional environment variable to report results in batches rather than after each test
case.
This helps reduce traffic to Testrail and also provides less flakiness in results not being posted when
something slow down testrail. To do this, add the following variable and set it to whatever number of test
case results you'd like to have posted at a time:

`TESTRAIL_BATCH_SIZE=15`

#### Setup
In your RSpec configuration file (usually spec_helper.rb) you need to call a registration function:

```ruby
RSpec.configure do |config|
  TestRailRSpecIntegration.register_rspec_integration(config,:bridge)
end
```

Here you pass in the rspec config and an identifier you how you want to label your test id.

:bridge:
`:testrail_id`
:canvas
`:test_id`


#### How to Use
For each spec that you want to report on, you will need to tag it with the testcase id from tetrail. If this is done, the rspec results will automatically be reported for that testcase to the sepcified run.

example:
`it 'can do something nifty', :testrail_id => [1234] do`

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

To publish gem to rubygems.org
a) Once the code change is complete, increase the version number
b) After the code is merged, run `gem build testrailtagging.gemspec`
d) Create a profile at rubygems.org, run `gem push testrailtagging-0.3.6.x.gem`
see http://guides.rubygems.org/publishing/

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/testrailtagging. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
