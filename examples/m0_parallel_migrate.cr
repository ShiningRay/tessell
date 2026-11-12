# M0-WP2 C1 migration observation sample (single run).
# 8 fibers × 3 yields on a Parallel context; each fiber records tid sequence.
# Reports migrated_any=<bool> fibers=8. Sample conclusion only — do NOT interpret as "will not migrate".

require "mutex"

fibers_n = 8
yields_n = 3

# tids[f][y] = Thread.current.object_id observed by fiber f at yield step y
tids = Array(Array(UInt64)).new(fibers_n) { Array(UInt64).new(yields_n, 0_u64) }
done = Channel(Nil).new
record_mu = Mutex.new

par = Fiber::ExecutionContext::Parallel.new("worker-migrate", 4)

fibers_n.times do |fi|
  par.spawn do
    seq = Array(UInt64).new(yields_n, 0_u64)
    yields_n.times do |yi|
      seq[yi] = Thread.current.object_id
      Fiber.yield
    end
    record_mu.synchronize { tids[fi] = seq }
    done.send(nil)
  end
end

fibers_n.times { done.receive }

migrated_fibers = 0
tids.each_with_index do |seq, fi|
  first = seq[0]?
  migrated = first.nil? ? false : seq.any? { |tid| tid != first }
  migrated_fibers += 1 if migrated
  puts "fiber=#{fi} tids=#{seq.join(",")} migrated=#{migrated}"
end

migrated_any = migrated_fibers > 0
puts "migrated_any=#{migrated_any} fibers=#{fibers_n} migrated_fibers=#{migrated_fibers} yields=#{yields_n}"
