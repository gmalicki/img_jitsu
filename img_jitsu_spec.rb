require "rubygems"
require "spec"
require 'img_jitsu'

describe Media do  
  before do
    @s3_config = YAML.load_file(Merb.root + '/config/amazon_s3.yml')[Merb.env].symbolize_keys!
    @sqs_connection = RightAws::Sqs.new(@s3_config['access_key_id'], @s3_config['secret_access_key'])
    @queue = RightAws::Sqs::Queue.create(@sqs_connection, @s3_config['in_queue'], true)
  end
  
  it "should process all media from the in-queue when asked to do so" do
    @queue.send_message({:image => { :id => 31337, :url => "http://www.google.com/intl/en_ALL/images/logo.gif" }}.to_yaml)
    Media.process_media
    1.should == 1
  end
  
  # it "should be able to make some copies of the downloaded file" do
  #   @m = Media.new('http://www.google.com/intl/en_ALL/images/logo.gif', 31337)
  #   @m.process.should == true
  #   # @m.send(:download).should == true
  #   # @m.send(:resize).should == true
  #   # @m.send(:sync_to_primary_storage).should == true
  #   # @m.send(:report).should == true
  # end
end