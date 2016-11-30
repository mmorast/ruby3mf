require 'spec_helper'

describe Log3mf do

  let(:log_levels) { [:fatal_error, :error, :warning, :info, :debug] }

  let(:log) { Log3mf.instance }

  describe 'when fatal_error is logged' do
    it 'should raise a Log3mf::FatalError' do
      expect {
        log.context "context for fatal_error test" do |l|
          log.fatal_error("Fatal Error")
        end
      }.to raise_error { |e|
        expect(e).to be_a(Log3mf::FatalError)
      }
    end
  end

  describe "testing all levels of log" do
    it "should have all kinds entries on log" do
      ENV['LOGDEBUG']='true'
      log_levels.each do |level|
        log.context "context for #{level} test" do |l|
          log.send(level.to_sym, level) rescue nil
          expect(Log3mf.entries(level.to_sym).count).to be >= 1
          expect(Log3mf.count_entries(level.to_sym)).to be >= 1
        end
      end
    end
  end

  describe 'spec links' do
    let(:specs) {
      {
        core: 'http://3mf.io/wp-content/uploads/2016/03/3MFcoreSpec_1.1.pdf',
        material: 'http://3mf.io/wp-content/uploads/2015/04/3MFmaterialsSpec_1.0.1.pdf',
        production: 'http://3mf.io/wp-content/uploads/2016/07/3MFproductionSpec.pdf',
        slice: 'http://3mf.io/wp-content/uploads/2016/07/3MFsliceSpec.pdf'
      }
    }

    it 'should default to core spec' do
      log.context "context for test spec links" do |l|
        log.error("Fatal Error", page: 11)
        json = JSON.parse(Log3mf.to_json)
        expect(json.first["spec_ref"]).to eq("http://3mf.io/wp-content/uploads/2016/03/3MFcoreSpec_1.1.pdf#page=11")
      end
    end

    it 'should reference proper specification when supplied' do
      log.context "context for test spec links" do |l|
        specs.each do |k, v|
          log.error("Fatal Error", spec: k.to_sym, page: 1)
          json = JSON.parse(Log3mf.to_json)
          expect(json.first["spec_ref"]).to eq("#{specs[k.to_sym]}#page=1")
          Log3mf.reset_log
        end
      end
    end
  end

  describe 'external access' do
    let(:result) {
      [{context: "context for to_hash spec",
        severity: :error,
        message: "This is an error",
        spec_ref: "http://3mf.io/wp-content/uploads/2016/03/3MFcoreSpec_1.1.pdf#page=14"},
       {context: "context for to_hash spec",
        severity: :warning,
        message: "This is a Warning",
        spec_ref: "http://3mf.io/wp-content/uploads/2016/03/3MFcoreSpec_1.1.pdf#page=15"},
       {context: "context for to_hash spec",
        severity: :info,
        message: "This is just Info",
        spec_ref: "http://3mf.io/wp-content/uploads/2016/03/3MFcoreSpec_1.1.pdf#page=16"}]
    }
    let(:logstuff) {
      log.context "context for to_hash spec" do |l|
        l.error("This is an error", page: 14)
        l.warning("This is a Warning", page: 15)
        l.info("This is just Info", page: 16)
      end
    }

    describe 'to_hash' do
      it 'should respond with logged items in Hash' do
        logstuff
        log_hash = Log3mf.to_hash
        expect(log_hash).to be_a(Array)
        expect(log_hash).to eq result
      end
    end

    describe 'to_json' do
      it 'should respond with logged items in JSON' do
        logstuff
        expect(Log3mf.to_json).to eq result.to_json
      end
    end
  end
end
