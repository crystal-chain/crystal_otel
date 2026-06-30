require 'spec_helper'
require 'crystal_otel/instrumentation/neo4j'

RSpec.describe CrystalOtel::Instrumentation::Neo4j do
  describe '.statement_text' do
    it 'extracts #to_cypher from an ActiveGraph::Core::Query-like object' do
      klass = Class.new { def to_cypher(*) = 'MATCH (n) RETURN n' }
      expect(described_class.statement_text(klass.new)).to eq('MATCH (n) RETURN n')
    end

    it 'uses a raw String as-is' do
      expect(described_class.statement_text('RAW STRING')).to eq('RAW STRING')
    end

    it 'falls back through #cypher and #text' do
      with_cypher = Struct.new(:cypher).new('MERGE (p:Product)')
      with_text = Struct.new(:text).new('CREATE (x)')
      expect(described_class.statement_text(with_cypher)).to eq('MERGE (p:Product)')
      expect(described_class.statement_text(with_text)).to eq('CREATE (x)')
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
      expect(described_class.trace_query('MATCH (n) RETURN n') { :result }).to eq(:result)
    end

    it 'does not trace when neo4j_tracing is disabled' do
      CrystalOtel.configuration.neo4j_tracing = false
      expect(described_class.tracing_enabled?).to be(false)
      expect(described_class.trace_query('MATCH (n)') { :ran }).to eq(:ran)
    end
  end

  describe CrystalOtel::Instrumentation::Neo4j::QueryInstrumentation do
    let(:base) do
      Class.new do
        # Mimics ActiveGraph::Base.query(*args); returns the args so we can
        # assert forwarding through the prepend.
        def query(*args)
          args
        end
      end
    end

    let(:instrumented) do
      klass = Class.new(base)
      klass.prepend(described_class)
      klass
    end

    it 'forwards a raw Cypher string to super' do
      expect(instrumented.new.query('MATCH (n) RETURN n')).to eq([ 'MATCH (n) RETURN n' ])
    end

    it 'forwards a query object plus options to super' do
      query = Class.new { def to_cypher(*) = 'CREATE (p)' }.new
      expect(instrumented.new.query(query, wrap: false)).to eq([ query, { wrap: false } ])
    end
  end
end
