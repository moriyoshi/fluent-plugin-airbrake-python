# encoding: utf-8
$:.push File.expand_path('../lib', __FILE__)

Gem::Specification.new do |gem|
  gem.name        = "fluent-plugin-airbrake-python"
  gem.description = "Airbrake (Python) plugin for Fluentd"
  gem.homepage    = "https://github.com/moriyoshi/fluent-plugin-airbrake-python"
  gem.summary     = gem.description
  gem.version     = File.read("VERSION").strip
  gem.authors     = ["Moriyoshi Koizumi"]
  gem.email       = "mozo@mozo.jp"
  gem.has_rdoc    = false
  gem.files       = `git ls-files`.split($/)
  gem.test_files  = `git ls-files -- {test,spec,features}/*`.split($/)
  gem.executables = `git ls-files -- bin/*`.split($/).map{ |f| File.basename(f) }
  gem.require_paths = ['lib']

  gem.add_dependency "fluentd", ">= 0"
  gem.add_dependency "airbrake", ">= 3.1"
end
