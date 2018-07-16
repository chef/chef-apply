require "spec_helper"
require "chef_apply/cli"
require "chef_apply/error"
RSpec.describe ChefApply::CLIValidation do
  class Validator
    include ChefApply::CLIValidation
  end
  subject { Validator.new }

  context "#validate_params" do
    OptionValidationError = ChefApply::CLI::OptionValidationError
    it "raises an error if not enough params are specified" do
      params = [
        [],
        %w{one}
      ]
      params.each do |p|
        expect { subject.validate_params(p) }.to raise_error(OptionValidationError) do |e|
          e.id == "CHEFVAL002"
        end
      end
    end

    it "succeeds if the second command is a valid file path" do
      params = %w{target /some/path}
      expect(File).to receive(:exist?).with("/some/path").and_return true
      expect { subject.validate_params(params) }.to_not raise_error
    end

    it "succeeds if the second argument looks like a cookbook name" do
      params = [
        %w{target cb},
        %w{target cb::recipe}
      ]
      params.each do |p|
        expect { subject.validate_params(p) }.to_not raise_error
      end
    end

    it "raises an error if the second argument is neither a valid path or a valid cookbook name" do
      params = %w{target weird%name}
      expect { subject.validate_params(params) }.to raise_error(OptionValidationError) do |e|
        e.id == "CHEFVAL004"
      end
    end

    it "raises an error if properties are not specified as key value pairs" do
      params = [
        %w{one two three four},
        %w{one two three four=value five six=value},
        %w{one two three non.word=value},
      ]
      params.each do |p|
        expect { subject.validate_params(p) }.to raise_error(OptionValidationError) do |e|
          e.id == "CHEFVAL003"
        end
      end
    end
  end
  describe "#properties_from_string" do
    it "parses properties into a hash" do
      provided = %w{key1=value key2=1 key3=true key4=FaLsE key5=0777 key6=https://some.website key7=num1and2digit key_8=underscore}
      expected = {
        "key1" => "value",
        "key2" => 1,
        "key3" => true,
        "key4" => false,
        "key5" => "0777",
        "key6" => "https://some.website",
        "key7" => "num1and2digit",
        "key_8" => "underscore"
      }
      expect(subject.properties_from_string(provided)).to eq(expected)
    end
  end

end

