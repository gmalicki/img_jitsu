require "rubygems"
require "spec"
require 'img_jitsu'

describe Media do  
  it "should be able to make some copies of the downloaded file" do
    @m = Media.new('http://www.google.com/intl/en_ALL/images/logo.gif', 31337)
    @m.process.should == true
    # @m.send(:download).should == true
    # @m.send(:resize).should == true
    # @m.send(:sync_to_primary_storage).should == true
    # @m.send(:report).should == true
  end
end