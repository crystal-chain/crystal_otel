require 'spec_helper'
require 'crystal_otel/instrumentation/neo4j'

RSpec.describe CrystalOtel::Instrumentation::Neo4j do
  describe '.statement_text' do
    it 'extracts #cypher from an ActiveGraph query object' do
      query = Struct.new(:cypher).new('MATCH (n) RETURN n')
      expect(described_class.statement_text(query)).to eq('MATCH (n) RETURN n')
    end

    it 'falls back to #to_cypher' do
      klass = Class.new { def to_cypher(*) = 'MERGE (p:Product)' }
      expect(described_class.statement_text(klass.new)).to eq('MERGE (p:Product)')
    end

    it 'falls back to #text, then to_s' do
      with_text = Struct.new(:text).new('CREATE (x)')
      expect(described_class.statement_text(with_text)).to eq('CREATE (x)')
      expect(described_class.statement_text('RAW STRING')).to eq('RAW STRING')
    end
  end

  describe '.obfuscate' do
    it 'masks single- and double-quoted string literals' do
      cypher = %(MATCH (n {name: 'secret', code: "abc"}) RETURN n)
      expect(described_class.obfuscate(cypher)).to eq(%(MATCH (n {name: '?', code: "?"}) RETURN n))
    end

    it 'leaves numeric literals and structure intact' do
      expect(described_class.obfuscate('MATCH (n) RETURN n LIMIT 25')).to eq('MATCH (n) RETURN n LIMIT 25')
    end
  end

  describe '.operation' do
    it 'returns the upcased leading keyword' do
      expect(described_class.operation('  match (n) return n')).to eq('MATCH')
      expect(described_class.operation('MERGE (p)')).to eq('MERGE')
    end

    it 'returns nil for an empty statement' do
      expect(described_class.operation('')).to be_nil
    end
  end

  describe '.trace_query' do
    it 'runs the block untraced and returns its value when OpenTelemetry is absent' do
      # OpenTelemetry is not loaded in the plain-Ruby unit suite, so tracing is
      # disabled and the block must still run exactly once.
      query = Struct.new(:cypher).new('MATCH (n) RETURN n')
      expect(described_class.trace_query(query) { :result }).to eq(:result)
    end

    it 'does not trace when neo4j_tracing is disabled' do
      CrystalOtel.configuration.neo4j_tracing = false
      expect(described_class.tracing_enabled?).to be(false)
      expect(described_class.trace_query('MATCH (n)') { :ran }).to eq(:ran)
    end
  end

  describe CrystalOtel::Instrumentation::Neo4j::QueryRunInstrumentation do
    let(:base) do
      Class.new do
        # Mimics ActiveGraph::Base.query_run(query, options = {}); returns the
        # args so we can assert forwarding through the prepend.
        def query_run(query, options = {})
          [ query, options ]
        end
      end
    end

    let(:instrumented) do
      klass = Class.new(base)
      klass.prepend(described_class)
      klass
    end

    it 'forwards the query and options to super' do
      query = Struct.new(:cypher).new('MATCH (n) RETURN n')
      expect(instrumented.new.query_run(query, wrap: true)).to eq([ query, { wrap: true } ])
    end

    it 'defaults options and still calls super' do
      query = Struct.new(:cypher).new('CREATE (p)')
      expect(instrumented.new.query_run(query)).to eq([ query, {} ])
    end
  end
end
