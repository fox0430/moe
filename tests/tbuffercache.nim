#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
#                                                                              #
#  This program is free software: you can redistribute it and/or modify        #
#  it under the terms of the GNU General Public License as published by        #
#  the Free Software Foundation, either version 3 of the License, or           #
#  (at your option) any later version.                                         #
#                                                                              #
#  This program is distributed in the hope that it will be useful,             #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of              #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
#  GNU General Public License for more details.                                #
#                                                                              #
#  You should have received a copy of the GNU General Public License           #
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.      #
#                                                                              #
#[############################################################################]#

import std/[unittest, options, tables, times, importutils]

import pkg/results

import moepkg/[bufferstatus, unicodeext, highlight, gapbuffer]

import moepkg/buffercache {.all.}

# Helper function to create a mock buffer with content
proc createMockBuffer(path: string, lines: int = 10): BufferStatus =
  result = initBufferStatus(Mode.normal).get
  result.path = ru(path)
  # Add some content to test memory estimation
  for i in 1 .. lines:
    result.buffer.add(ru("Line " & $i & " with some content"))

suite "BufferCache":
  test "Initialize cache":
    var cache = initBufferCache(maxCacheSize = 5, maxMemoryMB = 50)
    check cache.maxCacheSize == 5
    check cache.maxMemoryMB == 50
    check cache.cache.len == 0
    check cache.enabled == true

  test "Initialize cache with custom parameters":
    var cache = initBufferCache(maxCacheSize = 3, maxMemoryMB = 25, enabled = false)
    check cache.maxCacheSize == 3
    check cache.maxMemoryMB == 25
    check cache.enabled == false

  test "Enable/disable cache":
    var cache = initBufferCache()
    check cache.enabled == true

    # Add a buffer first
    var bufStatus = createMockBuffer("test.txt")
    cache.addToCache(bufStatus)
    check cache.cache.len == 1

    # Disable cache should clear everything
    cache.setEnabled(false)
    check cache.enabled == false
    check cache.cache.len == 0
    check cache.currentMemoryBytes == 0

    # Re-enable
    cache.setEnabled(true)
    check cache.enabled == true

  test "Add buffer to cache":
    var cache = initBufferCache()
    var bufStatus = createMockBuffer("test.txt")

    cache.addToCache(bufStatus)

    check cache.isInCacheByPath("test.txt")
    check cache.cache.len == 1
    check cache.currentMemoryBytes > 0

  test "Add buffer to disabled cache":
    var cache = initBufferCache(enabled = false)
    var bufStatus = createMockBuffer("test.txt")

    cache.addToCache(bufStatus)

    check not cache.isInCacheByPath("test.txt")
    check cache.cache.len == 0

  test "Update existing buffer in cache":
    privateAccess(BufferStatus)

    var cache = initBufferCache()
    var bufStatus = createMockBuffer("test.txt", 5)
    cache.addToCache(bufStatus)

    let initialMemory = cache.currentMemoryBytes

    # Update with more content
    var updatedBufStatus = createMockBuffer("test.txt", 20)
    updatedBufStatus.id = bufStatus.id # Same ID
    cache.addToCache(updatedBufStatus)

    check cache.cache.len == 1
    check cache.currentMemoryBytes != initialMemory

  test "Get buffer from cache by ID":
    var cache = initBufferCache()
    var bufStatus = createMockBuffer("test.txt")

    cache.addToCache(bufStatus)

    let cached = cache.getFromCache(bufStatus.id)
    check cached.isSome
    check cache.hitCount == 1

  test "Get buffer from cache by path":
    var cache = initBufferCache()
    var bufStatus = createMockBuffer("test.txt")

    cache.addToCache(bufStatus)

    let cached = cache.getFromCacheByPath("test.txt")
    check cached.isSome
    check cache.hitCount == 1

  test "Get buffer from disabled cache":
    var cache = initBufferCache()
    var bufStatus = createMockBuffer("test.txt")
    cache.addToCache(bufStatus)

    cache.setEnabled(false)

    let cached = cache.getFromCache(bufStatus.id)
    check cached.isNone
    check cache.missCount == 1

  test "Cache miss statistics":
    var cache = initBufferCache()

    let cached1 = cache.getFromCacheByPath("nonexistent.txt")
    let cached2 = cache.getFromCache(999)

    check cached1.isNone
    check cached2.isNone
    check cache.missCount == 2
    check cache.hitCount == 0

  test "Cache hit statistics and LRU update":
    var cache = initBufferCache()
    var bufStatus = createMockBuffer("test.txt")

    cache.addToCache(bufStatus)

    # First access
    let cached1 = cache.getFromCacheByPath("test.txt")
    check cached1.isSome
    check cache.hitCount == 1

    # Second access
    let cached2 = cache.getFromCache(bufStatus.id)
    check cached2.isSome
    check cache.hitCount == 2
    check cache.missCount == 0

  test "LRU eviction by cache size":
    var cache = initBufferCache(maxCacheSize = 2)

    # Add first buffer
    var buf1 = createMockBuffer("test1.txt")
    cache.addToCache(buf1)

    # Add second buffer
    var buf2 = createMockBuffer("test2.txt")
    cache.addToCache(buf2)

    check cache.cache.len == 2
    check cache.getCachedBufferIds().len == 2

    # Add third buffer - should evict first
    var buf3 = createMockBuffer("test3.txt")
    cache.addToCache(buf3)

    check cache.cache.len == 2
    check not cache.isInCacheByPath("test1.txt") # First buffer should be evicted
    check cache.isInCacheByPath("test2.txt")
    check cache.isInCacheByPath("test3.txt")

  test "LRU eviction by memory limit":
    # Create a cache with very small memory limit
    var cache = initBufferCache(maxCacheSize = 10, maxMemoryMB = 1)

    # Add buffers with large content until memory limit is reached
    var buffers: seq[BufferStatus] = @[]
    for i in 1 .. 5:
      var buf = createMockBuffer("test" & $i & ".txt", 1000) # Large buffers
      buffers.add(buf)
      cache.addToCache(buf)

    # Should have evicted some buffers due to memory constraints
    check cache.cache.len < 5
    check cache.currentMemoryBytes <= (1 * 1024 * 1024) # Within 1MB limit

  test "LRU access order update":
    var cache = initBufferCache(maxCacheSize = 3)

    # Add three buffers
    var buf1 = createMockBuffer("test1.txt")
    var buf2 = createMockBuffer("test2.txt")
    var buf3 = createMockBuffer("test3.txt")

    cache.addToCache(buf1)
    cache.addToCache(buf2)
    cache.addToCache(buf3)

    # Access buf1 to move it to most recent
    discard cache.getFromCache(buf1.id)

    # Add fourth buffer - buf2 should be evicted (oldest unused)
    var buf4 = createMockBuffer("test4.txt")
    cache.addToCache(buf4)

    check cache.cache.len == 3
    check cache.isInCacheByPath("test1.txt") # Recently accessed
    check not cache.isInCacheByPath("test2.txt") # Should be evicted
    check cache.isInCacheByPath("test3.txt")
    check cache.isInCacheByPath("test4.txt")

  test "Save and restore buffer state":
    var cache = initBufferCache()
    var bufStatus = createMockBuffer("test.txt")
    cache.addToCache(bufStatus)

    # Create a mock highlight object
    var highlight = initHighlight()

    # Save buffer state
    cache.saveBufferState(
      bufStatus.id,
      cursorLine = 5,
      cursorColumn = 10,
      expandedColumn = 15,
      scrollY = 2,
      scrollX = 3,
      highlight = highlight,
      version = 1,
    )

    let cached = cache.getFromCache(bufStatus.id)
    check cached.isSome

    if cached.isSome:
      let state = cached.get.state
      check state.cursorLine == 5
      check state.cursorColumn == 10
      check state.expandedColumn == 15
      check state.scrollY == 2
      check state.scrollX == 3
      check state.version == 1

  test "Save state for non-existent buffer":
    var cache = initBufferCache()
    var highlight = initHighlight()

    # Try to save state for buffer not in cache
    cache.saveBufferState(
      999, # Non-existent buffer ID
      cursorLine = 5,
      cursorColumn = 10,
      expandedColumn = 15,
      scrollY = 2,
      scrollX = 3,
      highlight = highlight,
    )

    # Should not crash or affect cache
    check cache.cache.len == 0

  test "Remove buffer from cache":
    var cache = initBufferCache()
    var bufStatus = createMockBuffer("test.txt")

    cache.addToCache(bufStatus)
    check cache.isInCacheByPath("test.txt")
    check cache.cache.len == 1

    let initialMemory = cache.currentMemoryBytes

    cache.removeFromCache(bufStatus.id)

    check not cache.isInCacheByPath("test.txt")
    check cache.cache.len == 0
    check cache.currentMemoryBytes < initialMemory

  test "Remove non-existent buffer":
    var cache = initBufferCache()
    var bufStatus = createMockBuffer("test.txt")
    cache.addToCache(bufStatus)

    # Try to remove non-existent buffer
    cache.removeFromCache(999)

    # Original buffer should still be there
    check cache.isInCacheByPath("test.txt")
    check cache.cache.len == 1

  test "Memory estimation":
    var cache = initBufferCache()

    # Small buffer
    var smallBuf = createMockBuffer("small.txt", 1)
    cache.addToCache(smallBuf)
    let smallMemory = cache.currentMemoryBytes

    cache.clearCache()

    # Large buffer
    var largeBuf = createMockBuffer("large.txt", 100)
    cache.addToCache(largeBuf)
    let largeMemory = cache.currentMemoryBytes

    check largeMemory > smallMemory

  test "Path mapping consistency":
    var cache = initBufferCache()
    var bufStatus = createMockBuffer("test.txt")

    cache.addToCache(bufStatus)

    # Check both path and ID mappings work
    check cache.isInCache(bufStatus.id)
    check cache.isInCacheByPath("test.txt")

    # Remove and check both are cleaned up
    cache.removeFromCache(bufStatus.id)

    check not cache.isInCache(bufStatus.id)
    check not cache.isInCacheByPath("test.txt")

  test "Clear cache":
    var cache = initBufferCache()
    var buf1 = createMockBuffer("test1.txt")
    var buf2 = createMockBuffer("test2.txt")

    cache.addToCache(buf1)
    cache.addToCache(buf2)

    # Generate some statistics
    discard cache.getFromCache(buf1.id)
    discard cache.getFromCache(999) # Miss

    check cache.cache.len == 2
    check cache.hitCount > 0
    check cache.missCount > 0
    check cache.currentMemoryBytes > 0

    cache.clearCache()

    check cache.cache.len == 0
    check cache.hitCount == 0
    check cache.missCount == 0
    check cache.currentMemoryBytes == 0

  test "Cache statistics":
    var cache = initBufferCache()
    var bufStatus = createMockBuffer("test.txt")
    cache.addToCache(bufStatus)

    # Generate hits and misses
    discard cache.getFromCache(bufStatus.id) # Hit
    discard cache.getFromCache(bufStatus.id) # Hit
    discard cache.getFromCache(999) # Miss
    discard cache.getFromCacheByPath("nonexistent.txt") # Miss

    let stats = cache.getCacheStats()
    check stats.hits == 2
    check stats.misses == 2
    check stats.hitRate == 0.5
    check stats.memoryMB > 0.0

  test "Cache statistics with no activity":
    var cache = initBufferCache()
    let stats = cache.getCacheStats()

    check stats.hits == 0
    check stats.misses == 0
    check stats.hitRate == 0.0
    check stats.memoryMB == 0.0

  test "Get cached buffer IDs":
    var cache = initBufferCache()

    check cache.getCachedBufferIds().len == 0

    var buf1 = createMockBuffer("test1.txt")
    var buf2 = createMockBuffer("test2.txt")

    cache.addToCache(buf1)
    cache.addToCache(buf2)

    let ids = cache.getCachedBufferIds()
    check ids.len == 2
    check buf1.id in ids
    check buf2.id in ids

  test "Empty path handling":
    var cache = initBufferCache()
    var bufStatus = initBufferStatus(Mode.normal).get
    # Leave path empty

    cache.addToCache(bufStatus)

    # Should still be in cache by ID but not by path
    check cache.isInCache(bufStatus.id)
    check not cache.isInCacheByPath("")

  test "Buffer state timestamps":
    var cache = initBufferCache()
    var bufStatus = createMockBuffer("test.txt")
    cache.addToCache(bufStatus)

    let timeBefore = now()

    # Access buffer to update timestamp
    discard cache.getFromCache(bufStatus.id)

    let cached = cache.getFromCache(bufStatus.id)
    check cached.isSome

    if cached.isSome:
      # Should have updated access time
      check cached.get.lastAccessTime >= timeBefore
