# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{bahn}
  s.version = "1.0.2"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Matt Westcott"]
  s.date = %q{2009-05-17}
  s.description = %q{A library for accessing train information from Deutsche Bahn in an object-oriented way}
  s.email = ["matt@west.co.tt"]
  s.extra_rdoc_files = ["History.txt", "Manifest.txt", "README.txt"]
  s.files = ["History.txt", "Manifest.txt", "README.txt", "Rakefile", "lib/bahn.rb", "test/test_bahn.rb"]
  s.has_rdoc = true
  s.rdoc_options = ["--main", "README.txt"]
  s.require_paths = ["lib"]
  s.rubyforge_project = %q{bahn}
  s.rubygems_version = %q{1.3.1}
  s.summary = %q{A library for accessing train information from Deutsche Bahn in an object-oriented way}
  s.test_files = ["test/test_bahn.rb"]
  s.homepage = "http://github.com/gasman/bahn/tree/master"
 
  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 2

    if Gem::Version.new(Gem::RubyGemsVersion) >= Gem::Version.new('1.2.0') then
      s.add_development_dependency(%q<hoe>, [">= 1.12.2"])
    else
      s.add_dependency(%q<hoe>, [">= 1.12.2"])
    end
  else
    s.add_dependency(%q<hoe>, [">= 1.12.2"])
  end
end
