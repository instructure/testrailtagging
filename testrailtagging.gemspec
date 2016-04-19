# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'files/version'

Gem::Specification.new do |spec|
  spec.name          = "testrailtagging"
  spec.version       = Testrailtagging::VERSION
  spec.authors       = ["Chris Johnson"]
  spec.email         = ["cjohnson@instructure.com"]

  spec.summary       = "Utilities for working with testrail."
  spec.description   = "Contains code for pushing rspec results up to testrail."
  spec.homepage      = "https://github.com/instructure/testrailtagging"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.11"
  spec.add_development_dependency "rake", "~> 10.0"

  spec.add_dependency 'testrail_client'
  spec.add_dependency 'parser'
  spec.add_dependency 'rspec'
end
