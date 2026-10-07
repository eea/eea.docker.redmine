# frozen_string_literal: true

require 'digest'

module EeaPatches
  # One source for tracker colors. Rendering never persists defaults to the DB.
  module TrackerColors
    NAMED_COLORS = {
      'green' => '#008000', 'blue' => '#0000ff', 'turquoise' => '#40e0d0',
      'lightgreen' => '#90ee90', 'yellow' => '#ffff00', 'orange' => '#ffa500',
      'red' => '#ff0000', 'purple' => '#800080', 'gray' => '#808080',
      'grey' => '#808080', 'dimgray' => '#696969'
    }.freeze
    LEGACY_NAMES = {
      'bug' => '#e5123d', 'feature' => '#0065ff', 'task' => '#614ba6',
      'support' => '#e67e22', 'change-request-normal' => '#6c757d'
    }.freeze
    LEGACY_IDS = {
      7 => '#008000', 8 => '#c0392b', 10 => '#0056b3',
      12 => '#6c3483', 13 => '#d35400'
    }.freeze

    module_function

    def normalize(value)
      value = value.to_s.strip.downcase
      return NAMED_COLORS[value] if NAMED_COLORS.key?(value)
      return value if value.match?(/\A#[0-9a-f]{6}\z/)
      return '#' + value[1..].chars.map { |c| c * 2 }.join if value.match?(/\A#[0-9a-f]{3}\z/)

      nil
    end

    def for_tracker(tracker)
      record = tracker.agile_color if tracker.respond_to?(:agile_color)
      explicit = record.color if record
      configured = normalize(explicit)
      return configured if configured

      name = tracker.name.to_s.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-|-\z/, '')
      legacy_name = LEGACY_NAMES[name] if tracker.id && tracker.id <= 13
      LEGACY_IDS[tracker.id] || legacy_name || generated(tracker.id || "name:#{tracker.name}")
    end

    def generated(identity)
      # Golden-angle spacing keeps adjacent IDs apart. A digest handles unsaved
      # trackers without Ruby's process-dependent String#hash.
      number = identity.is_a?(Integer) ? identity : Digest::SHA256.hexdigest(identity.to_s)[0, 12].to_i(16)
      hue = (number * 137.50776405003785) % 360 / 60.0
      chroma = 0.50
      secondary = chroma * (1 - (hue % 2 - 1).abs)
      channels = case hue.floor
                 when 0 then [chroma, secondary, 0]
                 when 1 then [secondary, chroma, 0]
                 when 2 then [0, chroma, secondary]
                 when 3 then [0, secondary, chroma]
                 when 4 then [secondary, 0, chroma]
                 else [chroma, 0, secondary]
                 end
      '#%02x%02x%02x' % channels.map { |channel| ((channel + 0.14) * 255).round }
    end

    def rgb(color)
      color.delete_prefix('#').scan(/../).map { |channel| channel.to_i(16) }
    end

    def mix(color, target, weight)
      '#%02x%02x%02x' % rgb(color).map { |channel| (channel * (1 - weight) + target * weight).round }
    end

    def luminance(color)
      channels = rgb(color).map do |channel|
        value = channel / 255.0
        value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4
      end
      channels.zip([0.2126, 0.7152, 0.0722]).sum { |channel, weight| channel * weight }
    end

    def foreground(color)
      luminance(color) > 0.179 ? '#000000' : '#ffffff'
    end

    def css_class(tracker)
      "taskman-tracker-color-#{for_tracker(tracker).delete_prefix('#')}"
    end

    def css_rule(color)
      hover = mix(color, 0, 0.2)
      ".taskman-tracker-color-#{color.delete_prefix('#')} {" \
        "--taskman-tracker-color:#{color};" \
        "--taskman-tracker-text:#{foreground(color)};" \
        "--taskman-tracker-hover:#{hover};" \
        "--taskman-tracker-hover-text:#{foreground(hover)};" \
        "--taskman-tracker-tint:#{mix(color, 255, 0.85)};}"
    end
  end
end
