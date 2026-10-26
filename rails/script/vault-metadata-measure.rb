#!/usr/bin/env ruby
# Synthetic buffers only. No Rails, database, Vault root or input file is opened.
require "json"
require "open3"
require "rbconfig"
require_relative "../app/services/vault/document"
require_relative "../app/services/vault/metadata/identity_set"

module VaultMetadataMeasure
  module_function

  def workloads
    %w[small header_limit unicode_scalar depth_16 nodes_4096 mapping_256 sequence_512 lines_2048 body_2m depth_over nodes_over alias_bomb batch_10000 batch_partial batch_entries_over batch_retained_over]
  end

  def buffer(name)
    base = "accio_schema: 1\nid: synthetic"
    yaml = case name
    when "small", "body_2m" then base
    when "header_limit"
      base + "\n#" + "x" * (65_536 - 8 - base.bytesize - 3)
    when "unicode_scalar" then base + "\ntitle: #{'é' * 4096}"
    when "depth_16", "depth_over"
      depth = name == "depth_16" ? 15 : 16
      base + "\nx: #{'[' * depth}x#{']' * depth}"
    when "nodes_4096", "nodes_over"
      total = name == "nodes_4096" ? 4081 : 4082
      arrays = 8.times.map { |i| "[#{([ 'x' ] * (total / 8 + (i < total % 8 ? 1 : 0))).join(',')}]" }
      base + "\nx: [#{arrays.join(',')}]"
    when "mapping_256" then base + "\n" + 254.times.map { |i| "k#{i}: v" }.join("\n")
    when "sequence_512" then base + "\nx: [#{([ 'x' ] * 512).join(',')}]"
    when "lines_2048" then base + "\n" + "#\n" * 2045
    when "alias_bomb" then base + "\na: &a [x,x]\nb: &b [*a,*a]\nc: [*b,*b]"
    end
    raw = "---\n#{yaml}\n---\n".b
    raw << "x" * (2_097_152 - raw.bytesize) if name == "body_2m"
    raw
  end

  def entries(count = 10_000, large_ids: false)
    count.times.map do |i|
      { path: "n#{i}.md", kind: :note, sha256: Digest::SHA256.hexdigest("synthetic-#{i}"),
        claimed_id: large_ids ? "id#{i}".ljust(4096, "x") : "id#{i}", source_read_state: :complete, parse_status: :valid, local_classification: :managed }
    end
  end

  def peak_kib
    File.read("/proc/self/status").match(/^VmHWM:\s+(\d+)/)[1].to_i
  end

  def worker(name, mode)
    input = if name == "batch_entries_over" then entries(10_001)
    elsif name == "batch_retained_over" then entries(10_000, large_ids: true)
    elsif name.start_with?("batch") then entries
    else buffer(name)
    end
    samples = []
    statuses, codes, counts = [], [], {}
    GC.start
    baseline = peak_kib
    20.times do
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      if mode == "parse"
        if name.start_with?("batch")
          reductions = name == "batch_partial" ? { identity_bytes: 4096 } : {}
          result = Vault::Metadata::IdentitySet.call(input, scope: "synthetic", complete: true,
            parser_limits: Vault::Metadata::Limits.new(**reductions))
          statuses << (result.coverage.values.all? ? "complete" : "partial")
          codes.concat(result.diagnostics.map { |d| d[:code].to_s })
          counts = { entries: result.entries.size, text_bytes: result.text_bytes }
        else
          result = Vault::Document.from_bytes(input)
          statuses << result.parse_status.to_s
          codes.concat(result.diagnostics.map { |d| d[:code].to_s })
          counts = result.metrics
        end
      end
      samples << (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
      result = nil
      GC.start
    end
    raise "unexpected database load" if defined?(Rails) || defined?(ActiveRecord) || $LOADED_FEATURES.any? { |f| f.include?("sqlite3") }
    { workload: name, mode: mode, repeats: samples.size, times_ms: samples, p95_ms: samples.sort[18],
      vmhwm_kib: peak_kib, baseline_kib: baseline, statuses: statuses.uniq, codes: codes.uniq.sort,
      counts: counts, input_bytes: input.is_a?(String) ? input.bytesize : nil }
  end
end

if ARGV.first == "--worker"
  puts JSON.generate(VaultMetadataMeasure.worker(ARGV.fetch(1), ARGV.fetch(2)))
else
  rows = VaultMetadataMeasure.workloads.map do |name|
    pair = %w[control parse].to_h do |mode|
      output, error, status = Open3.capture3(RbConfig.ruby, __FILE__, "--worker", name, mode)
      raise "measurement failed: #{name}/#{mode}: #{error}" unless status.success?
      [ mode, JSON.parse(output) ]
    end
    actual = pair.fetch("parse")
    expected = if name == "depth_over" || name == "nodes_over" then "limit_exceeded"
    elsif name == "alias_bomb" then "invalid"
    elsif name == "batch_10000" then "complete"
    elsif %w[batch_partial batch_entries_over batch_retained_over].include?(name) then "partial"
    else "valid"
    end
    growth = [ actual.fetch("vmhwm_kib") - pair.fetch("control").fetch("vmhwm_kib"), 0 ].max
    gate_kib = name.start_with?("batch") ? 128 * 1024 : 32 * 1024
    raise "resource/status gate failed: #{name}" unless actual.fetch("statuses") == [ expected ] && growth <= gate_kib
    warn "#{name}: #{expected}, p95=#{actual.fetch('p95_ms').round(3)}ms, HWM delta=#{growth}KiB"
    { workload: name, expected: expected, vmhwm_growth_kib: growth, memory_gate_kib: gate_kib, passed: true, workers: pair }
  end
  puts JSON.pretty_generate({ ruby: RUBY_DESCRIPTION, psych: Psych::VERSION, libyaml: Psych.libyaml_version,
    kernel: `uname -srmo`.strip, protocol: "20 repetitions, fresh control/parse processes per workload; GC outside timing; VmHWM observational, not enforced RSS", rows: rows })
end
