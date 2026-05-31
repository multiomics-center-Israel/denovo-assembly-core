require 'sequenceserver/links'

# Adds a "View in JBrowse" link to each BLAST hit row, deep-linking to the
# Spalangia cameroni assembly at the hit's subject coordinates.
module SequenceServer
  module Links
    def jbrowse
      sstarts = hsps.map(&:sstart)
      sends   = hsps.map(&:send)
      from = [sstarts.min, sends.min].min
      to   = [sstarts.max, sends.max].max
      assembly = 'spalangia_cameroni'
      track    = 'spalangia_cameroni-ReferenceSequenceTrack'
      loc = "#{id}:#{from}-#{to}"
      url = "http://localhost:8080/?assembly=#{assembly}" \
            "&loc=#{loc}&tracks=#{track}"
      {
        url: url,
        title: 'View in JBrowse',
        icon_class: 'fa fa-external-link',
        order: 4,
      }
    end
  end
end
