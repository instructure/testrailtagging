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

## Usage

First, you must have a valid and active testrail account you want to post results to.
Second to use the API's you will need a username and a password for testrail.

Hence to do anything with this gem you will need to set the following environment variables:
 
`TESTRAIL_USER`
`TESTRAIL_PASSWORD`

which this gem will look for and use.
 
### For Reporting results to testrail

This is for reporting rspec results to a pre-existing test run at testrail.com.
First, in testrail find the ID of the test run you want to push results to. You can find it in URL like this:

`https://blablabla.testrail.com/index.php?/runs/view/14153`

Here the test run is 14153.

Then you set an environment variable called TESTRAIL_RUN_ID, with that value. For example:

`export TESTRAIL_RUN_ID=14153`

Next, in your RSpec configuration file (usually spec_helper.rb) you need to call a registration function: 


```ruby
RSpec.configure do |config|
  TestRailRSpecIntegration.register_rspec_integration(config,:bridge)
end
```

Here you pass in the rspec config, and an identifier for your product. Either :bridge or :canvas.


## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/testrailtagging. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

