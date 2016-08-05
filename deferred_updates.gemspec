lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "deferred_updates/version"

Gem::Specification.new do |s|
  s.name        = 'deferred_updates'
  s.version     = DeferredUpdates::VERSION
  s.summary     = "Defer low-priority database INSERTs and UPDATEs to a later time, to reduce contention"
  s.description = %q{ Deferred Updates queues up databse INSERTs and UPDATEs that don't need to happen
                      immediately, and runs them in batches later. Running them in batches is much more
                      efficient than running them one by one, reducing total time running the updates,
                      load on the database server, and contention due to locking of those rows.
                   }
  s.authors     = ["Daniel Magliola"]
  s.email       = 'dmagliola@crystalgears.com'
  s.homepage    = 'https://github.com/dmagliola/deferred_updates'
  s.license     = 'MIT'

  s.files       = `git ls-files`.split($/)
  s.executables   = s.files.grep(%r{^bin/}) { |f| File.basename(f) }
  s.test_files    = s.files.grep(%r{^(test|s.features)/})
  s.require_paths = ["lib"]

  s.required_ruby_version = ">= 1.9.3"

  s.add_runtime_dependency "activerecord", ">= 3.2"

  s.add_development_dependency "connection_pool"
  s.add_development_dependency "redis", '>= 3.0'

  s.add_development_dependency "bundler"
  s.add_development_dependency "rake"

  s.add_development_dependency "minitest"
  s.add_development_dependency "minitest-reporters"
  s.add_development_dependency "shoulda"
  s.add_development_dependency "mocha"
  s.add_development_dependency "simplecov"

  s.add_development_dependency "appraisal"
  s.add_development_dependency "coveralls"
  s.add_development_dependency "codeclimate-test-reporter"
end
