#!/usr/bin/env ruby
# encoding: US-ASCII

# vim: set sts=2 noet ts=2:
#
#   ProfanityFE v0.4
#   Copyright (C) 2013  Matthew Lowe
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License along
#   with this program; if not, write to the Free Software Foundation, Inc.,
#   51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#
#   matt@lichproject.org
#

$version = 0.82

require 'socket'
require 'rexml/document'
require 'curses'
include Curses

Curses.init_screen
Curses.start_color
Curses.cbreak
Curses.noecho

class Skill
  def initialize(name, ranks, percent, mindstate)
    @name = name
    @ranks = ranks
    @percent = percent
    @mindstate = mindstate
  end

  def to_s
    format('%8s:%5d %2s%% [%2s/34]', @name, @ranks, @percent, @mindstate)
  end

  def to_str
    format('%8s:%5d %2s%% [%2s/34]', @name, @ranks, @percent, @mindstate)
  end
end

class ExpWindow < Curses::Window
  attr_reader :color_stack, :buffer
  attr_accessor :scrollbar, :indent_word_wrap, :layout, :time_stamp

  @@list = []

  def self.list
    @@list
  end

  def initialize(*args)
    @skills = {}
    @open = false
    @@list.push(self)
    super(*args)
  end

  def delete_skill
    return unless @current_skill

    @skills.delete(@current_skill)
    redraw
    @current_skill = ''
  end

  def set_current(skill)
    @current_skill = skill
  end

  def add_string(text, _line_colors)
    return unless text =~ %r{(.+):\s*(\d+) (\d+)%  \[\s*(\d+)/34\]}

    # if text =~ /(\w+(\s\w+)?)<\/d>:\s+(\d+)(?:\s+)(\d{1,2}|100)%\s+\[\s?(\d+)\/34\]/
    name = ::Regexp.last_match(1).strip
    ranks = ::Regexp.last_match(2)
    percent = ::Regexp.last_match(3)
    mindstate = ::Regexp.last_match(4)

    skill = Skill.new(name, ranks, percent, mindstate)
    @skills[@current_skill] = skill
    redraw
    @current_skill = ''
  end

  def skill_group_color(skill)
    armor = ['Shield', 'Lt Armor', 'Chain', 'Brig', 'Plate', 'Defend', 'Convict']

    weapon = %w[Parry SE LE 2HE SB LB 2HB Slings Bows Crossbow Staves Polearms LT HT Brawling Offhand Melee Missile
                Expert]

    magic = %w[Magic IF IM Attune Arcana TM Aug Debil Util Warding Sorcery Astro Summon Theurgy]

    survival = %w[Evasion Athletic Perc Stealth Locks Thievery FA Outdoors Skinning BS Scouting Than Backstab]

    lore = %w[Forging Eng Outfit Alchemy Enchant Scholar Mech Appraise Perform Tactics BardLore Empathy Trading]

    if armor.include? skill
      '00FF00' # green
    elsif weapon.include? skill
      '00FFFF' # cyan
    elsif magic.include? skill
      'FF0000' # red
    elsif survival.include? skill
      'FF00FF' # magenta
    elsif lore.include? skill
      'FFFF00' # yellow
    end
  end

  def mindstate_color(mindstate)
    if mindstate == 0
      'FFFFFF' # white
    elsif (1..10).member?(mindstate)
      '00FFFF' # cyan
    elsif (11..20).member?(mindstate)
      '00FF00' # green
    elsif (21..30).member?(mindstate)
      'FFFF00' # yellow
    elsif (31..34).member?(mindstate)
      'FF0000' # red
    end
  end

  def add_skill(skill, skill_colors = [])

    SETTINGS_LOCK.synchronize do
      HIGHLIGHT.each_pair do |regex, colors|
        pos = 0
        while (match_data = skill.match(regex, pos))
          h = {
            start: match_data.begin(0),
            end: match_data.end(0),
            fg: colors[0],
            bg: colors[1],
            ul: colors[2]
          }
          skill_colors.push(h)
          pos = match_data.end(0)
        end
      end
    end

    # addstr skill
    part = [0, skill.length]
    skill_colors.each do |h|
      part.push(h[:start])
      part.push(h[:end])
    end
    part.uniq!
    part.sort!
    for i in 0...(part.length - 1)
      str = skill[part[i]...part[i + 1]]
      color_list = skill_colors.find_all { |h| (h[:start] <= part[i]) and (h[:end] >= part[i + 1]) }
      if color_list.empty?
        addstr str
        noutrefresh
      else
        color_list = color_list.sort_by { |h| h[:end] - h[:start] }
        fg = color_list.map { |h| h[:fg] }.find { |fg| !fg.nil? }
        bg = color_list.map { |h| h[:bg] }.find { |bg| !bg.nil? }
        ul = color_list.map { |h| h[:ul] == 'true' }.find { |ul| ul }
        attron(color_pair(get_color_pair_id(fg, bg)) | (ul ? Curses::A_UNDERLINE : Curses::A_NORMAL)) do
          addstr str
          noutrefresh
        end
      end
    end
  end

  def redraw
    clear
    setpos(0, 0)

    @skills.sort.each do |_name, skill|
      # addstr skill.to_s + "\n"
      add_skill(skill.to_s)
      # addstr(skill)
      addstr("\n")
      noutrefresh
    end
    noutrefresh
  end
end

class PercWindow < Curses::Window
  attr_reader :color_stack, :buffer
  attr_accessor :scrollbar, :indent_word_wrap, :layout, :time_stamp

  @@list = []

  def ExpWindow.list
    @@list
  end

  def initialize(*args)
    @buffer = []
    @buffer_pos = 0
    @max_buffer_size = 250
    @indent_word_wrap = true
    @@list.push(self)
    super(*args)
  end

  def add_line(line, line_colors = [])
    part = [0, line.length]
    line_colors.each do |h|
      part.push(h[:start])
      part.push(h[:end])
    end
    part.uniq!
    part.sort!
    for i in 0...(part.length - 1)
      str = line[part[i]...part[i + 1]]
      color_list = line_colors.find_all { |h| (h[:start] <= part[i]) and (h[:end] >= part[i + 1]) }
      if color_list.empty?
        addstr str + "\n" unless str.chomp.empty?
        noutrefresh
      else
        # shortest length highlight takes precedence when multiple highlights cover the same substring
        # fixme: allow multiple highlights on a substring when one specifies fg and the other specifies bg
        color_list = color_list.sort_by { |h| h[:end] - h[:start] }
        fg = color_list.map { |h| h[:fg] }.find { |fg| !fg.nil? }
        bg = color_list.map { |h| h[:bg] }.find { |bg| !bg.nil? }
        ul = color_list.map { |h| h[:ul] == 'true' }.find { |ul| ul }
        attron(color_pair(get_color_pair_id(fg, bg)) | (ul ? Curses::A_UNDERLINE : Curses::A_NORMAL)) do
          addstr str + "\n" unless str.chomp.empty?
          noutrefresh
        end
      end
      noutrefresh
    end
  end

  def add_string(string, string_colors = [])
    while (line = string.slice!(/^.{2,#{maxx - 1}}(?=\s|$)/)) or (line = string.slice!(0, (maxx - 1)))
      line_colors = []
      for h in string_colors
        line_colors.push(h.dup) if h[:start] < line.length
        h[:end] -= line.length
        h[:start] = [(h[:start] - line.length), 0].max
      end
      string_colors.delete_if { |h| h[:end] < 0 }
      line_colors.each { |h| h[:end] = [h[:end], line.length].min }
      @buffer.unshift([line, line_colors])
      @buffer.pop if @buffer.length > @max_buffer_size
      if @buffer_pos == 0
        add_line(line, line_colors)
        # addstr "\n"
      else
        @buffer_pos += 1
        scroll(1) if @buffer_pos > (@max_buffer_size - maxy)
        update_scrollbar
      end
      break if string.chomp.empty?

      if @indent_word_wrap
        if string[0, 1] == ' '
          string = " #{string}"
          string_colors.each do |h|
            h[:end] += 1
            # Never let the highlighting hang off the edge -- it looks weird
            h[:start] += h[:start] == 0 ? 2 : 1
          end
        else
          string = "#{string}"
          string_colors.each do |h|
            h[:end] += 2
            h[:start] += 2
          end
        end
      elsif string[0, 1] == ' '
        string = string[1, string.length]
        string_colors.each do |h|
          h[:end] -= 1
          h[:start] -= 1
        end
      end
    end
  end

  def redraw
    clear
    setpos(0, 0)
    noutrefresh
  end

  def clear_spells
    clear
    setpos(0, 0)
    noutrefresh
  end
end

class TextWindow < Curses::Window
  attr_reader :color_stack, :buffer, :max_buffer_size
  attr_accessor :scrollbar, :indent_word_wrap, :layout, :time_stamp

  @@list = []

  def self.list
    @@list
  end

  def initialize(*args)
    @buffer = []
    @buffer_pos = 0
    @max_buffer_size = 250
    @indent_word_wrap = true
    @@list.push(self)
    super(*args)
  end

  def max_buffer_size=(val)
    # FIXME: minimum size?  Curses.lines?
    @max_buffer_size = val.to_i
  end

  def add_line(line, line_colors = [])
    part = [0, line.length]
    line_colors.each do |h|
      part.push(h[:start])
      part.push(h[:end])
    end
    part.uniq!
    part.sort!
    for i in 0...(part.length - 1)
      str = line[part[i]...part[i + 1]]
      color_list = line_colors.find_all { |h| (h[:start] <= part[i]) and (h[:end] >= part[i + 1]) }
      if color_list.empty?
        addstr str
      else
        # shortest length highlight takes precedence when multiple highlights cover the same substring
        # fixme: allow multiple highlights on a substring when one specifies fg and the other specifies bg
        color_list = color_list.sort_by { |h| h[:end] - h[:start] }
        fg = color_list.map { |h| h[:fg] }.find { |fg| !fg.nil? }
        bg = color_list.map { |h| h[:bg] }.find { |bg| !bg.nil? }
        ul = color_list.map { |h| h[:ul] == 'true' }.find { |ul| ul }
        attron(color_pair(get_color_pair_id(fg, bg)) | (ul ? Curses::A_UNDERLINE : Curses::A_NORMAL)) do
          addstr str
        end
      end
    end
  end

  def add_string(string, string_colors = [])
    #
    # word wrap string, split highlights if needed so each wrapped line is independent, update buffer, update window if needed
    #
    if @time_stamp && string && !string.chomp.empty?
      string += " [#{Time.now.hour.to_s.rjust(2,
                                              '0')}:#{Time.now.min.to_s.rjust(2,
                                                                              '0')}]"
    end
    while (line = string.slice!(/^.{2,#{maxx - 1}}(?=\s|$)/)) or (line = string.slice!(0, (maxx - 1)))
      line_colors = []
      for h in string_colors
        line_colors.push(h.dup) if h[:start] < line.length
        h[:end] -= line.length
        h[:start] = [(h[:start] - line.length), 0].max
      end
      string_colors.delete_if { |h| h[:end] < 0 }
      line_colors.each { |h| h[:end] = [h[:end], line.length].min }
      @buffer.unshift([line, line_colors])
      @buffer.pop if @buffer.length > @max_buffer_size
      if @buffer_pos == 0
        addstr "\n" unless line.chomp.empty?
        add_line(line, line_colors)
      else
        @buffer_pos += 1
        scroll(1) if @buffer_pos > (@max_buffer_size - maxy)
        update_scrollbar
      end
      break if string.chomp.empty?

      if @indent_word_wrap
        if string[0, 1] == ' '
          string = " #{string}"
          string_colors.each do |h|
            h[:end] += 1
            # Never let the highlighting hang off the edge -- it looks weird
            h[:start] += h[:start] == 0 ? 2 : 1
          end
        else
          string = "  #{string}"
          string_colors.each do |h|
            h[:end] += 2
            h[:start] += 2
          end
        end
      elsif string[0, 1] == ' '
        string = string[1, string.length]
        string_colors.each do |h|
          h[:end] -= 1
          h[:start] -= 1
        end
      end
    end
    return unless @buffer_pos == 0

    noutrefresh
  end

  def scroll(scroll_num)
    if scroll_num < 0
      scroll_num = 0 - (@buffer.length - @buffer_pos - maxy) if (@buffer_pos + maxy + scroll_num.abs) >= @buffer.length
      if scroll_num < 0
        @buffer_pos += scroll_num.abs
        scrl(scroll_num)
        setpos(0, 0)
        pos = @buffer_pos + maxy - 1
        scroll_num.abs.times do
          add_line(@buffer[pos][0], @buffer[pos][1])
          addstr "\n"
          pos -= 1
        end
        noutrefresh
      end
      update_scrollbar
    elsif scroll_num > 0
      if @buffer_pos == 0
        nil
      else
        scroll_num = @buffer_pos if (@buffer_pos - scroll_num) < 0
        @buffer_pos -= scroll_num
        scrl(scroll_num)
        setpos(maxy - scroll_num, 0)
        pos = @buffer_pos + scroll_num - 1
        (scroll_num - 1).times do
          add_line(@buffer[pos][0], @buffer[pos][1])
          addstr "\n"
          pos -= 1
        end
        add_line(@buffer[pos][0], @buffer[pos][1])
        noutrefresh
      end
    end
    update_scrollbar
  end

  def update_scrollbar
    return unless @scrollbar

    last_scrollbar_pos = @scrollbar_pos
    @scrollbar_pos = maxy - ((@buffer_pos / [(@buffer.length - maxy), 1].max.to_f) * (maxy - 1)).round - 1
    if last_scrollbar_pos
      unless last_scrollbar_pos == @scrollbar_pos
        @scrollbar.setpos(last_scrollbar_pos, 0)
        @scrollbar.addch '|'
        @scrollbar.setpos(@scrollbar_pos, 0)
        @scrollbar.attron(Curses::A_REVERSE) do
          @scrollbar.addch ' '
        end
        @scrollbar.noutrefresh
      end
    else
      for num in 0...maxy
        @scrollbar.setpos(num, 0)
        if num == @scrollbar_pos
          @scrollbar.attron(Curses::A_REVERSE) do
            @scrollbar.addch ' '
          end
        else
          @scrollbar.addch '|'
        end
      end
      @scrollbar.noutrefresh
    end
  end

  def clear_scrollbar
    @scrollbar_pos = nil
    @scrollbar.clear
    @scrollbar.noutrefresh
  end

  def resize_buffer
    # fixme
  end
end

class ProgressWindow < Curses::Window
  attr_accessor :fg, :bg, :label, :layout
  attr_reader :value, :max_value

  @@list = []

  def self.list
    @@list
  end

  def initialize(*args)
    @label = String.new
    @fg = []
    @bg = %w[0000aa 000055]
    @value = 100
    @max_value = 100
    @@list.push(self)
    super(*args)
  end

  def update(new_value, new_max_value = nil)
    new_max_value ||= @max_value
    if (new_value == @value) and (new_max_value == @max_value)
      false
    else
      @value = new_value
      @max_value = [new_max_value, 1].max
      redraw
    end
  end

  def redraw
    str = "#{@label}#{@value.to_s.rjust(maxx - @label.length)}"
    percent = [[(@value / @max_value.to_f), 0.to_f].max, 1].min
    if (@value == 0) and (fg[3] or bg[3])
      setpos(0, 0)
      attron(color_pair(get_color_pair_id(@fg[3], @bg[3])) | Curses::A_NORMAL) do
        addstr str
      end
    else
      left_str = str[0, (str.length * percent).floor].to_s
      if (@fg[1] or @bg[1]) and (left_str.length < str.length) and (((left_str.length + 0.5) * (1 / str.length.to_f)) < percent)
        middle_str = str[left_str.length, 1].to_s
      else
        middle_str = ''
      end
      right_str = str[(left_str.length + middle_str.length), (@label.length + (maxx - @label.length))].to_s
      setpos(0, 0)
      if left_str.length > 0
        attron(color_pair(get_color_pair_id(@fg[0], @bg[0])) | Curses::A_NORMAL) do
          addstr left_str
        end
      end
      if middle_str.length > 0
        attron(color_pair(get_color_pair_id(@fg[1], @bg[1])) | Curses::A_NORMAL) do
          addstr middle_str
        end
      end
      if right_str.length > 0
        attron(color_pair(get_color_pair_id(@fg[2], @bg[2])) | Curses::A_NORMAL) do
          addstr right_str
        end
      end
    end
    noutrefresh
    true
  end
end

class CountdownWindow < Curses::Window
  attr_accessor :label, :fg, :bg, :end_time, :secondary_end_time, :active, :layout
  attr_reader :value, :secondary_value

  @@list = []

  def self.list
    @@list
  end

  def initialize(*args)
    @label = String.new
    @fg = []
    @bg = [nil, 'ff0000', '0000ff']
    @active = nil
    @end_time = 0
    @secondary_end_time = 0
    @@list.push(self)
    super(*args)
  end

  def update
    old_value = @value
    old_secondary_value = @secondary_value
    @value = [(@end_time.to_f - Time.now.to_f + $server_time_offset.to_f - 0.2).ceil, 0].max
    @secondary_value = [(@secondary_end_time.to_f - Time.now.to_f + $server_time_offset.to_f - 0.2).ceil, 0].max
    if (old_value != @value) or (old_secondary_value != @secondary_value) or (@old_active != @active)
      str = "#{@label}#{[@value, @secondary_value].max.to_s.rjust(maxx - @label.length)}"
      setpos(0, 0)
      if ((@value == 0) and (@secondary_value == 0)) or (@active == false)
        if @active
          str = "#{@label}#{'?'.rjust(maxx - @label.length)}"
          left_background_str = str[0, 1].to_s
          right_background_str = str[left_background_str.length, (@label.length + (maxx - @label.length))].to_s
          attron(color_pair(get_color_pair_id(@fg[1], @bg[1])) | Curses::A_NORMAL) do
            addstr left_background_str
          end
          attron(color_pair(get_color_pair_id(@fg[2], @bg[2])) | Curses::A_NORMAL) do
            addstr right_background_str
          end
        else
          attron(color_pair(get_color_pair_id(@fg[0], @bg[0])) | Curses::A_NORMAL) do
            addstr str
          end
        end
      else
        left_background_str = str[0, @value].to_s
        secondary_background_str = str[left_background_str.length, (@secondary_value - @value)].to_s
        right_background_str = str[(left_background_str.length + secondary_background_str.length),
                                   (@label.length + (maxx - @label.length))].to_s
        if left_background_str.length > 0
          attron(color_pair(get_color_pair_id(@fg[1], @bg[1])) | Curses::A_NORMAL) do
            addstr left_background_str
          end
        end
        if secondary_background_str.length > 0
          attron(color_pair(get_color_pair_id(@fg[2], @bg[2])) | Curses::A_NORMAL) do
            addstr secondary_background_str
          end
        end
        if right_background_str.length > 0
          attron(color_pair(get_color_pair_id(@fg[3], @bg[3])) | Curses::A_NORMAL) do
            addstr right_background_str
          end
        end
      end
      @old_active = @active
      noutrefresh
      true
    else
      false
    end
  end
end

class IndicatorWindow < Curses::Window
  @@list = []

  def self.list
    @@list
  end

  attr_accessor :fg, :bg, :layout
  attr_reader :label, :value

  def label=(str)
    @label = str
    redraw
  end

  def initialize(*args)
    @fg = %w[444444 ffff00]
    @bg = [nil, nil]
    @label = '*'
    @value = nil
    @@list.push(self)
    super(*args)
  end

  def update(new_value)
    if new_value == @value
      false
    else
      @value = new_value
      redraw
    end
  end

  def redraw
    setpos(0, 0)
    if @value
      if @value.is_a?(Integer)
        attron(color_pair(get_color_pair_id(@fg[@value], @bg[@value])) | Curses::A_NORMAL) { addstr @label }
      else
        attron(color_pair(get_color_pair_id(@fg[1], @bg[1])) | Curses::A_NORMAL) { addstr @label }
      end
    else
      attron(color_pair(get_color_pair_id(@fg[0], @bg[0])) | Curses::A_NORMAL) { addstr @label }
    end
    noutrefresh
    true
  end
end

server = nil
command_buffer        = String.new
command_buffer_pos    = 0
command_buffer_offset = 0
command_history       = []
command_history_pos   = 0
# max_command_history   = 20
min_cmd_length_for_history = 4
$server_time_offset     = 0
skip_server_time_offset = false
key_binding = {}
key_action = {}
need_prompt = false
prompt_text = '>'
stream_handler = {}
indicator_handler = {}
progress_handler = {}
countdown_handler = {}
command_window = nil
command_window_layout = nil
# We need a mutex for the settings because highlights can be accessed during a
# reload.  For now, it is just used to protect access to HIGHLIGHT, but if we
# ever support reloading other settings in the future it will have to protect
# those.
SETTINGS_LOCK = Mutex.new
HIGHLIGHT = {}
PRESET = {}
LAYOUT = {}
WINDOWS = {}
SCROLL_WINDOW = []

# gag strings here
combat_gag_patterns = [
  %r{^(?!(?:\*|\[|\<))}, # Matches everything in the combat window except (\[|\*|\<)
  # /^\[.*overwhelming (your)?\s?opponent/,
  /Roundtime/,
  /^You reveal/,
  /You're (?!hurt|beat up|very beat up|badly hurt|very badly hurt|smashed up).* balanced and .* (?:position|advantage)/,
  /.* at you\.  You (?:sidestep|dodge|evade|fend|slap|deflect|beat|counter|repulse|(partially|barely)?\s?block|turn|knock)/
]

gag_patterns = [
  %r{<preset id="whisper">\w+ whispers,</preset> "Done!"$},
  /^\w+ just touched \w+/,
  /^The leaves on your lirisan wristcuff/,
  /^The Imperial dira centered upon your leather armlet shimmers with silvery light/,
  /^\w+ begins to lecture \w+/,
  /^A painful lump rises in your throat as some nearby shadows darken and shift/,
  %r{\[Assuming you mean},
  /^Slowly the corpse of a bone wyvern decays into a mass of brittle old bone/,
  # %r{<pushStream id="combat" />\w+ (are revealed|feints|bashes|swings|lunges|chops|draws|thrusts|reveals|gouges|lobs|jabs|fires|slices|bobs)},
  # %r{<pushStream id="combat" />(<pushBold/>)?\w+'s \w+ lands},
  # %r{(?:<pushStream id="combat" />)? .* lands nearby\!$},
  # %r{^(?:<pushStream id="combat" />)?Its armored hide absorbs the impact},
  # %r{^<pushStream id="combat" />An ominous rustling comes from all around},
  # %r{^<pushStream id="combat" />Leaping from a bone wyvern},
  # %r{^<pushStream id="combat" />Vibrantly colorful},
  # %r{^(?:<pushStream id="combat" />)?\w+ manages?},
  %r{^(?:<.*>)?(?:The|A|An) (?:telga orek|ice archon|storm bull|(?:elder )?Adan'f blademaster|(?:bone|adult|young|juvenile) wyvern|jeol moradu|silver-grey cloud rat|(?:fuligin|void-black|shadowfrost)?\s?(?:umbral )?moth|Dragon Priest intercessor)},
  %r{^A storm bull},
  /\[.*(?:overwhelming|dominating) (your)?\s?opponent/,
  # /.* at you\.  You (?:sidestep|dodge|evade|fend|slap|deflect|beat|counter|repulse|(partially|barely)?\s?block|turn|knock)/,
  /^You stop advancing because a bone wyvern is dead/,
  /^I could not find what you were referring to/,
  /^\w+ drops a wyvern claw/,
  /^You search the/,
  /^You quickly pocket the coins.  Anything else of interest was added to the/,
  %r{^You gather up the loot you're interested in and stuff it in your},
  # /^The .* lands (?:a|an) \w+ (?:\(\d+\/23\) )?(?:hit|strike)/,
  /A blazing flame-like droplet lands/,
  %r{^(A|The) shimmering ethereal shield},
  /\w+ feints .* at a jeol moradu/,
  />A jeol moradu (feints|lunges|slices|thrusts)/,
  %r{^\w+ manages? to get out of the way of the spinning scythe!},
  /^The scythe swiftly melts away\./,
  /begins to listen to \w+ teach the Scholarship skill/,
  %r{<preset id="whisper">\w+ whispers,</preset> "heal"$},
  %r{<preset id="whisper">You whisper to \w+,</preset> "(heal|Thank you.)"$},
  /^You notice( as)? a sinewy leopard/,
  /^The serpent earcuff coils, sensing your danger/,
  /^Your wooden medallion warms in response to your danger/,
  /^Your purpleheart seed begins to pulsate/,
  /^The scavenger giant begins to incant a spell/,
  /^A dark cloud coalesces over the body of the scavenger giant/,
  /^A scavenger giant crashes to the ground and shudders for a moment/,
  /^(A scavenger giant gestures|A faint breeze surrounds (him|her))\./,
  /^One of the etched patterns upon your frozen-bone wristcuff/,
  /^Within the flow of whispered chanting nearby/,
  /^The viscous (solution drenches|goo burbles)/,
  /whirls about in a bold, flashy manner!$/,
  /visibly churns with an inner rage!$/,
  /^\w+ manages? to remain upright!/,
  /^The castoff flecks fade to black then vanish/,
  /^The stream of liquid silver-grey fire washes/,
  /^The .* lands at \w+('s)? feet/,
  /^You aren't close enough to attack/,
  /^What do you want to advance towards/,
  %r{^(<pushStream id="combat" />)?(?:A|The) hellish spiral},
  /^You are able to channel all the energy/,
  /^The .* absorbs all of the energy/,
  /^You are already advancing on/,
  /(?:wanders|runs|strolls|goes|drifts|went) (?:north|south|east|west|(?:north|south)east|west|up|down|across)\.$/,
  /just arrived\.$/,
  # %r{^<pushStream id="combat" />(?!(?:\*|\[|\<))}, # Matches everything in the combat window except (\[|\*|\>)
  # %r{^(<pushStream id="combat" />)?.*manages to get out of the way\!$},
  %r{You feel a chill as a spell breaches your ward\!},
  # %r{^(<pushStream id="combat" />)?.* (?:jumps? into the air|circles? back in midair) and zips?},
  # %r{^(<pushStream id="combat" />)?(?:A|The) (?:whirlwind|\w+ \w+ tendril)},
  # %r{^(<pushStream id="combat" />)?(?:The )?(?:B|b)lood.*bone wyvern},
  # %r{^<pushStream id="combat" />The air around},
  # %r{^<pushStream id="combat" />Sparkling crystals of ice},
  # %r{^<pushStream id="combat" />Intense waves of heat},
  # %r{^<pushStream id="combat" />A sheet of slippery ice forms beneath},
  # %r{^(<pushStream id="combat" />)?(Boiling tongues|Burning smoke|Tendrils of|(The|Another) (stream|trickles))},
  # %r{^(<pushStream id="combat" />)?The web of shadows},
  # %r{^(<pushStream id="combat" />)?The flames land},
  # %r{^(<pushStream id="combat" />)?The air around you},
  # %r{^(<pushStream id="combat" />)?Geysers of fiery},
  # %r{^(<pushStream id="combat" />)?A faint sizzling sound fills the air},
  # %r{^(<pushStream id="combat" />)?Blackened embers and flakes of ash},
  # %r{^(<pushStream id="combat" />)?The black radiance fades},
  # %r{^(<pushStream id="combat" />)?A cage of shadowy tendrils coalesces},
  # %r{^(<pushStream id="combat" />)?The swirling confines of malevolent darkness},
  # %r{^(<popStream id="combat" />)?(A|An|The) .* (feints|lunges|slices|thrusts|comes)},
  # %r{^(<popStream id="combat" />)?A group of the insects launch themselves},
  # %r{^<pushStream id="combat" />The air around \w+ begins to crackle with static electricity!},
  # %r{^<pushStream id="combat" />\w+ visibly quakes with an inner fury!},
  # %r{^<pushStream id="combat" />Small sparks of electricity dance},
  # %r{^(<pushStream id="combat" />)?The bugs finally cease swarming},
  # %r{^(<pushStream id="combat" />)?The bugs swarming around},
  # %r{^<pushStream id="combat" />The insects continue to swarm},
  # %r{^<pushStream id="combat" />The quaking fury inside of you continues unabated},
  # %r{^<pushStream id="assess"/><clearStream id="assess"/>You assess your combat situation},
  /^With a ghostly wail a bone wyvern charges into view with a rush of icy wind/,
  /^An icy wail cuts through the air as a bone wyvern soars into view/,
  /^A disturbing black radiance creeps over/,
  /^Blood pumping loudly, you whip about in a tumultuous fury/,
  /^The \w+ of your wristcuff flicker and you feel more battle-ready/,
  /^The nearby shadows swell before an elder Adan/,
  /^The chakrel dust upon the surface of your manacle glows for a moment/,
  /^\s+"?Adan'f (?:lusss|inja)/,
  /\w+ with a (sharp )?\*crack\*!$/,
  /^The taipan tightens its coils about your arm/,
  /^You bull-rush at/,
  /^The quaking fury inside of you continues unabated/,
  /^You struggle to maintain the quaking fury unleashed upon your enemies/,
  /^The air randomly discharges, leaving behind the scent of ozone/,
  /^The air around \w+ begins to crackle with static electricity/,
  /^The insects continue to swarm/,
  /^\w+ visibly quakes with an inner fury/,
  /^The air around \w+ begins to crackle with static electricity/,
  /^The air randomly discharges, leaving behind the scent of ozone/,
  /you notice a fuligin moth trying to/i,
  /^A nearby shadow darkens and expands, coalescing into a fuligin umbral moth/,
  /^The restraints binding a fuligin umbral moth grow soft and strange/,
  /is entangled by the encroaching web\.$/,
  /^The strong smell of ozone accompanies/,
  /(sprawls|slumps) wearily(?: and (passes out|drops like a rock), (dead to the world|having yielded to your lullaby))?\.$/,
  /^You sense deep traces of empathic shock within/,
  /^The molten Life flowing in your blood quickens you, every motion improving your balance/,
  /^You feel the warmth in your flesh gradually subside/,
  /^EXP HELP for more information/,
  /^An ice archon backs away from combat, sending a shower of ice shards from its body as it does so|An ice archon moves into view, dragging its feet and leaving huge snowy scratches behind it|An ice archon moves ponderously east, dragging its feet and leaving huge snowy scratches behind it|An ice archon raises its massive icy foot and brings it downward|A pile of broken ice slowly loses its shape and melts back into the landscape|A creaking noise of ice scraping against ice comes from the ice archon|^An ice archon|Appearing to have lost sight of its target, an ice archon stops advancing/,
  /climbed (down|up) a snow-covered cliff/,
  /^One of the planetary discs on your uthamar anklet briefly darkens as a sense/,
  /^Water drips from your thin-edged zills\./,
  /^Icy blue frost crackles up a jeol moradu/,
  /^A faint breeze surrounds it/,
  /^A jeol moradu (roars in frustration|howls in encouragement|walks \w+ with thundering steps|growls out a spell in a thunderous voice|melts away, its remains soaked up by the ground)/,
  /^With a thunderous stride, a jeol moradu arrives/,
  /^A soft crackle briefly comes from a jeol moradu's direction/,
  /^The ground shakes as a jeol moradu thunders in with a blast of frigid air/,
  /and is closing steadily\.$/,
  /^The battle-worn carcass of a \w+ wyvern rots away/,
  /^The \w+ wyvern (is still a distance away|slowly tips over and falls down)/,
  /^The battered form of a \w+ wyvern slowly decomposes into/,
  /^The \w+ wyvern's tail lashes at/,
  /^Glancing about, an? \w+ wyvern opens its mouth/,
  /^With a low growl an? \w+ wyvern skulks/,
  /^An? \w+ wyvern (snarls loudly in its sleep at it exhales a deep breath|shakes its head back and forth furiously with a low snarl|emits a guttural clicking snarl|rakes its black talons|grooms its scales carefully with its mouth|wakes up|slowly skulks into view with its head held low|begins to move again, the anesthetic|thrashes its leathery-black wings|fluidly leaps to its feet in a blur of motion|bounds into view with a throaty hiss|thrashes its long neck with an angry shriek|lurches forward to stab its tail stinger|suddenly draws in an sharp breath and lets out|hops into view|thrashes its head about with a tortured wail|wakes up|shakes its head back and forth furiously with a snarl|appears less distracted|draws in a deep breath with a \w+-pitched)/,
  /^You can no longer see openings in a young wyvern's defenses/,
  /^With its massive leathery-black wings bound in layers of sticky webbing/,
  /^A gutteral roar cuts through the air as an adult wyvern swoops down from the heavens/,
  /^Frozen in place, an adult wyvern's eyes sweep the area with a throaty snarl/,
  /\w+ drops some coins into the Darkbox and reaches inside it/,
  /removes \w+ hand from the Darkbox looking both relieved and disappointed/,
  /^A soft crackle briefly comes from a storm bull's direction/,
  /^While conventional spiders spin silk, elder wildling spiders spin wildlace/,
  /^Effectively immortal, wildling spiders live until killed/,
  /^Unlike conventional spiders, wildling spiders feed on mana/,
  /^Wildling spiders are a long-lived species/,
  /^It is the venom of wildling spiders that transforms ordinary Humans/,
  /^When the Spidersworn speak of themselves/,
  /^The Spidersworn follow the goddess Harawep/,
  /^Their purpose is to serve, translate, and speak for Harawep's creatures/,
  /^Is it possible to know the mind of a spider\?  A group that calls itself the Spidersworn/,
  /^However, nothing much else happens, as you lack the concentration to focus/,
  /^\w+ stops playing (her|his) song/,
  /^\w+ raises (her|his) hands skyward, chanting/,
  /morgawr bone armband flares with radiant light/,
  /^Several of the charms on/,
  /^\w+ gets a quiet, peaceful look on \w+ face/,
  /jaguar-pelt \w+ flicker briefly/,
  /^(With a slight \*tink!\*, an enriched crauyarin scuttler shatters into broken crystal|A single point of red light expands into a horizontal line|Flares of crystalline white luminance bloom around|Clear blue light falls about the crauyarin scuttler|Entangling their protuberances, a pair of crauyarin scuttlers flash|Sudden movement in your peripheral vision reveals a crauyarin scuttler crawling out from nothingness|Your vision skews wildly as several crystalline fractures appear across your field of vision)/,
  /^A crauyarin scuttler (swiftly skitters in, crackling like broken glass as it moves|exchanges semaphoric flashes|glows red and blue as it contorts oddly)/,
  /^(The)?\s?(Luminous cracks appear on|curvature of|Gossamer light skips across the arch of|A soft crackle briefly comes from|Great zigzag fissures break the circuit of|A hexagonal section of|crystalline white flares subside from around|Rearing back,)?\s?([Aa]n enriched)?\s?crauyarin scuttler( \w+ its \w+| begins to|'s blue)?/,
  /^Your (shield|(chain )?hauberk) \w+/,
  /^(?:A|The) blue-dappled prereni/,
  /^(?:Raising its head, )?(?:[aA]|The) storm bull.*/,
  /^(?:Sparks of electricity shimmer around a storm bull's body as it sways dazedly|Misty tendrils rise from the pale hide of a storm bull as it gazes alertly around the area|A musical note swells in the air as a storm bull brushes its horn against its leg|Horns lowered, a storm bull charges|Shifting from side to side, a storm bull crops at the grass underfoot)/,
  /stops? a .* from advancing any farther/,
  /^The .* begins to advance on/,
  /closes? to (melee|pole weapon) range on/,
  /^\w+ assesses (his|her) combat situation/,
  /^(Magical devices are, simply, devices that|A popular theory of magical genesis places the first magical devices|The mechanism for devices typically come in two forms|In addition, devices can be characterized as self-powered|There are some practical limits to these devices|Activation of a magical device can range|Due to the nature of mana incompatibility)/,
  /^The range of effects that Holy magic can conjure up is impressively wide/,
  /^\w+ (and the clerk share a few words|exchanges some words with the clerk)/,
  /^(A faint trail of gleaming|A trio of|One of the|Sparkles follow the|The).*multihued moons.*right forearm/,
  /multihued moons suddenly accelerate their chase of one another, causing their/,
  /A dull crimson glow radiates from \w+'s wooden medallion/,
  /closes to pole (weapon|melee) range on you!$/,
  /^Showing all skills with field experience/,
  /^Tiny vengeance rubies on \w+'s leather armband pulse with an ominous glow/,
  /^The tiny vengeance rubies scattered across your leather armband pulse with an ominous glow for a moment and you feel more focused/,
  /blighted gold bracelet flares with radiant light, and \w+ looks more at ease than before/,
  /a sense of peace and restfulness spreading through you to ease your mental fatigue/,
  /^Overall state of mind: clear/,
  /^\w+\s(begins?|finishes?).*(zills|cowbell).*/,
  /^\w+\s(gazes? intently into|exhales softly on) \w+ sanowret crystal.*/,
  /You hear in your mind a quiet recollection of wisdom/,
  /^You feel fully attuned to the mana streams again/,
  /^Knowledge from your sanowret crystal/,
  /^Attunement is a descriptive term referring to an individual magician's capacity/,
  /^Through guided meditation a nascent magician learns to see or feel the normally invisible/,
  /^The initial process of attunement can take anywhere from hours to/,
  /^Once attuned, a magician may then concentrate to feel/,
  /^Nearly everybody possesses the basic mental and physical capacity for attunement/,
  /^Fables exist about attunement the same as any other magical/,
  /^Holy magic is theoretically the oldest form of magic known/,
  /^Holy magic derives both its name and its power from the Immortals/,
  /^Moreso than any other discipline of magic, Holy magicians consider/,
  /^While Holy magic is powered by the activity of the Immortals, as a rule it/,
  /^It is fair to say that Holy magic has a moralistic bend, but this is found in the confounds/,
  /^Despite this discipline's strong connection to the Immortals, other entities have/,
  /^The light and crystal sound of your sanowret crystal fades slightly/,
  /^The spirit of the cheetah surges through your veins/,
  /^You exhale softly on your sanowret crystal/,
  /^With a \*click\*, your changes snap into place/,
  /^You fiddle with the tiny levers and dials of the \w+'s mechanical abdomen/,
  /^Delicate phofe flowers slowly drift and swirl across the ethereal surface/,
  /launches into the next verse/,
  /on (his|her).*cowbell/,
  /leans? forward.*(zills|cowbell)/,
  /^The \w+ comes alive in your hand/,
  /^It is mere moments afterward that you feel an itching/,
  /bends \w+ head over.*(zills|cowbell)/,
  /^A soft light blossoms in the very center of the crystal/,
  /^Life magic is perhaps the most mysterious realm to Kermorians/,
  /^Despite the name, Life mana is strongly identified with the natural processes of decay/,
  /^While sufficient Life magic can accelerate or delay the march of time upon an organism/,
  /^Despite this, both the Empaths and Rangers have made an art out of stretching the limits/,
  /^Life mana is created by or resonate with \(depending on your point of view\) with/,
  /^The history of Life magic is incomplete, in large part due to the disbanding/,
  /^Conspiracy theorists claim that the Empath Guild is suppressing knowledge/,
  /(crown|thighband) pulses with a soft light/,
  /pendant flash white for a moment/,
  /shimmer with a strikingly green (sheen|hue)/,
  /continues? to (play|perform).*(zills|cowbell)/,
  /^In the year 403, as the Spider was on its way to make its fourth appearance in Kermoria/,
  /^In the year 410, Kurmin and his engineers constructed a baby metal arachnid/,
  /^Physically and mentally altered, Kurmin babbled about many things/,
  /^That brings us to the year 432, when the Spider fell ill/,
  /^Will the Spider be able to recover?  Will it continue to be able to host merchants/,
  /you continue (to (play|perform)|playing your.*(zills|cowbell))/,
  /^You.*(play|begin).*(zills|cowbell)/,
  /^The youngest of the magical disciplines, Lunar magic's scholarly/,
  /^Lunar magic is, befitting the name, strongly affected by the rise and fall/,
  /^Due to the nature of the forces that Lunar mages use, the seemingly insubstantial/,
  /^Another facet of these forces is that they tend to be more volatile/,
  /^This volatility combined with a generally malicious edge to Lunar spells/,
  /^Archeological evidence proves that a highly advanced form of Lunar magic was/,
  /^Moon Mages specifically derive much of the character and power behind/,
  /^You're already playing a song/
]

gag_regexp = Regexp.union(gag_patterns)
combat_gag_regexp = Regexp.union(combat_gag_patterns)

def add_prompt(window, prompt_text, cmd = '')
  window.add_string("#{prompt_text}#{cmd}",
                    [{ start: 0, end: (prompt_text.length + cmd.length), fg: '555555' }])
end

for arg in ARGV
  if arg =~ /^--help|^-h|^-\?/
    puts ''
    puts "Profanity FrontEnd v#{$version}"
    puts ''
    puts '   --port=<port>'
    puts '   --default-color-id=<id>'
    puts '   --default-background-color-id=<id>'
    puts '   --custom-colors=<on|off>'
    puts '   --settings-file=<filename>'
    puts ''
    exit
  elsif arg =~ /^--port=([0-9]+)$/
    PORT = Regexp.last_match(1).to_i
  elsif arg =~ /^--default-color-id=(-?[0-9]+)$/
    DEFAULT_COLOR_ID = Regexp.last_match(1).to_i
  elsif arg =~ /^--default-background-color-id=(-?[0-9]+)$/
    DEFAULT_BACKGROUND_COLOR_ID = Regexp.last_match(1).to_i
  elsif arg =~ /^--use-default-colors$/
    USE_DEFAULT_COLORS = true
  elsif arg =~ /^--custom-colors=(on|off|yes|no)$/
    fix_setting = { 'on' => true, 'yes' => true, 'off' => false, 'no' => false }
    CUSTOM_COLORS = fix_setting[Regexp.last_match(1)]
  elsif arg =~ /^--settings-file=(.*?)$/
    SETTINGS_FILENAME = Regexp.last_match(1)
  end
end

LOCALUSERNAME = `whoami`

LOG_DIR = '.' unless defined?(LOG_DIR)

PORT = 8000 unless defined?(PORT)
LOG_FILENAME = PORT unless defined?(LOG_FILENAME)
DEFAULT_COLOR_ID = 7 unless defined?(DEFAULT_COLOR_ID)
DEFAULT_BACKGROUND_COLOR_ID = 0 unless defined?(DEFAULT_BACKGROUND_COLOR_ID)
Curses.use_default_colors if defined?(USE_DEFAULT_COLORS)
SETTINGS_FILENAME = File.expand_path('~/.profanity.xml') unless defined?(SETTINGS_FILENAME)
CUSTOM_COLORS = Curses.can_change_color? unless defined?(CUSTOM_COLORS)

DEFAULT_COLOR_CODE = Curses.color_content(DEFAULT_COLOR_ID).collect do |num|
  ((num / 1000.0) * 255).round.to_s(16)
end.join('').rjust(6, '0')
DEFAULT_BACKGROUND_COLOR_CODE = Curses.color_content(DEFAULT_BACKGROUND_COLOR_ID).collect do |num|
  ((num / 1000.0) * 255).round.to_s(16)
end.join('').rjust(6, '0')

xml_escape_list = {
  '&lt;'   => '<',
  '&gt;'   => '>',
  '&quot;' => '"',
  '&apos;' => "'",
  '&amp;'  => '&'
}

key_name = {
  'ctrl+a'        => 1,
  'ctrl+b'        => 2,
  #	'ctrl+c'    => 3,
  'ctrl+d'        => 4,
  'ctrl+e'        => 5,
  'ctrl+f'        => 6,
  'ctrl+g'        => 7,
  'ctrl+h'        => 8,
  'win_backspace' => 8,
  'ctrl+i'        => 9,
  'tab'           => 9,
  'ctrl+j'        => 10,
  'enter'         => 10,
  'ctrl+k'        => 11,
  'ctrl+l'        => 12,
  'return'        => 13,
  'ctrl+m'        => 13,
  'ctrl+n'        => 14,
  'ctrl+o'        => 15,
  'ctrl+p'        => 16,
  #	'ctrl+q'    => 17,
  'ctrl+r'        => 18,
  #	'ctrl+s'    => 19,
  'ctrl+t'        => 20,
  'ctrl+u'        => 21,
  'ctrl+v'        => 22,
  'ctrl+w'        => 23,
  'ctrl+x'        => 24,
  'ctrl+y'        => 25,
  #	'ctrl+z'    => 26,
  'alt'           => 27,
  'escape'        => 27,
  'ctrl+?'        => 127,
  'down'          => 258,
  'up'            => 259,
  'left'          => 260,
  'right'         => 261,
  'home'          => 262,
  'backspace'     => 263,
  'f1'            => 265,
  'f2'            => 266,
  'f3'            => 267,
  'f4'            => 268,
  'f5'            => 269,
  'f6'            => 270,
  'f7'            => 271,
  'f8'            => 272,
  'f9'            => 273,
  'f10'           => 274,
  'f11'           => 275,
  'f12'           => 276,
  'delete'        => 330,
  'insert'        => 331,
  'page_down'     => 338,
  'page_up'       => 339,
  'win_end'       => 358,
  'end'           => 360,
  'resize'        => 410,
  'num_7'         => 449,
  'num_8'         => 450,
  'num_9'         => 451,
  'num_4'         => 452,
  'num_5'         => 453,
  'num_6'         => 454,
  'num_1'         => 455,
  'num_2'         => 456,
  'num_3'         => 457,
  'num_enter'     => 459,
  'ctrl+delete'   => 513,
  'alt+down'      => 517,
  'ctrl+down'     => 519,
  'alt+left'      => 537,
  'ctrl+left'     => 539,
  'alt+page_down' => 542,
  'alt+page_up'   => 547,
  'alt+right'     => 552,
  'ctrl+right'    => 554,
  'alt+up'        => 558,
  'ctrl+up'       => 560
}

if CUSTOM_COLORS
  COLOR_ID_LOOKUP = {}
  COLOR_ID_LOOKUP[DEFAULT_COLOR_CODE] = DEFAULT_COLOR_ID
  COLOR_ID_LOOKUP[DEFAULT_BACKGROUND_COLOR_CODE] = DEFAULT_BACKGROUND_COLOR_ID
  COLOR_ID_HISTORY = []
  for num in 0...Curses.colors
    COLOR_ID_HISTORY.push(num) unless (num == DEFAULT_COLOR_ID) or (num == DEFAULT_BACKGROUND_COLOR_ID)
  end

  def get_color_id(code)
    if (color_id = COLOR_ID_LOOKUP[code])
      color_id
    else
      color_id = COLOR_ID_HISTORY.shift
      COLOR_ID_LOOKUP.delete_if { |_k, v| v == color_id }
      sleep 0.01 # somehow this keeps Curses.init_color from failing sometimes
      Curses.init_color(color_id, ((code[0..1].to_s.hex / 255.0) * 1000).round, ((code[2..3].to_s.hex / 255.0) * 1000).round,
                        ((code[4..5].to_s.hex / 255.0) * 1000).round)
      COLOR_ID_LOOKUP[code] = color_id
      COLOR_ID_HISTORY.push(color_id)
      color_id
    end
  end
else
  COLOR_CODE = %w[000000 800000 008000 808000 000080 800080 008080 c0c0c0 808080 ff0000
                  00ff00 ffff00 0000ff ff00ff 00ffff ffffff 000000 00005f 000087 0000af 0000d7 0000ff 005f00 005f5f 005f87 005faf 005fd7 005fff 008700 00875f 008787 0087af 0087d7 0087ff 00af00 00af5f 00af87 00afaf 00afd7 00afff 00d700 00d75f 00d787 00d7af 00d7d7 00d7ff 00ff00 00ff5f 00ff87 00ffaf 00ffd7 00ffff 5f0000 5f005f 5f0087 5f00af 5f00d7 5f00ff 5f5f00 5f5f5f 5f5f87 5f5faf 5f5fd7 5f5fff 5f8700 5f875f 5f8787 5f87af 5f87d7 5f87ff 5faf00 5faf5f 5faf87 5fafaf 5fafd7 5fafff 5fd700 5fd75f 5fd787 5fd7af 5fd7d7 5fd7ff 5fff00 5fff5f 5fff87 5fffaf 5fffd7 5fffff 870000 87005f 870087 8700af 8700d7 8700ff 875f00 875f5f 875f87 875faf 875fd7 875fff 878700 87875f 878787 8787af 8787d7 8787ff 87af00 87af5f 87af87 87afaf 87afd7 87afff 87d700 87d75f 87d787 87d7af 87d7d7 87d7ff 87ff00 87ff5f 87ff87 87ffaf 87ffd7 87ffff af0000 af005f af0087 af00af af00d7 af00ff af5f00 af5f5f af5f87 af5faf af5fd7 af5fff af8700 af875f af8787 af87af af87d7 af87ff afaf00 afaf5f afaf87 afafaf afafd7 afafff afd700 afd75f afd787 afd7af afd7d7 afd7ff afff00 afff5f afff87 afffaf afffd7 afffff d70000 d7005f d70087 d700af d700d7 d700ff d75f00 d75f5f d75f87 d75faf d75fd7 d75fff d78700 d7875f d78787 d787af d787d7 d787ff d7af00 d7af5f d7af87 d7afaf d7afd7 d7afff d7d700 d7d75f d7d787 d7d7af d7d7d7 d7d7ff d7ff00 d7ff5f d7ff87 d7ffaf d7ffd7 d7ffff ff0000 ff005f ff0087 ff00af ff00d7 ff00ff ff5f00 ff5f5f ff5f87 ff5faf ff5fd7 ff5fff ff8700 ff875f ff8787 ff87af ff87d7 ff87ff ffaf00 ffaf5f ffaf87 ffafaf ffafd7 ffafff ffd700 ffd75f ffd787 ffd7af ffd7d7 ffd7ff ffff00 ffff5f ffff87 ffffaf ffffd7 ffffff 080808 121212 1c1c1c 262626 303030 3a3a3a 444444 4e4e4e 585858 626262 6c6c6c 767676 808080 8a8a8a 949494 9e9e9e a8a8a8 b2b2b2 bcbcbc c6c6c6 d0d0d0 dadada e4e4e4 eeeeee][0...Curses.colors]
  COLOR_ID_LOOKUP = {}

  def get_color_id(code)
    if (color_id = COLOR_ID_LOOKUP[code])
      color_id
    else
      least_error = nil
      least_error_id = nil
      COLOR_CODE.each_index do |color_id|
        error = ((COLOR_CODE[color_id][0..1].hex - code[0..1].hex)**2) + ((COLOR_CODE[color_id][2..3].hex - code[2..3].hex)**2) + ((COLOR_CODE[color_id][4..6].hex - code[4..6].hex)**2)
        if least_error.nil? or (error < least_error)
          least_error = error
          least_error_id = color_id
        end
      end
      COLOR_ID_LOOKUP[code] = least_error_id
      least_error_id
    end
  end
end

# COLOR_PAIR_LIST = Array.new
# for num in 1...Curses::color_pairs
#	COLOR_PAIR_LIST.push h={ :color_id => nil, :background_id => nil, :id => num }
# end

# 157+12+1 = 180
# 38+1+6 = 45
# 32767

COLOR_PAIR_ID_LOOKUP = {}
COLOR_PAIR_HISTORY = []

# FIXME: high color pair id's change text?
# A_NORMAL = 0
# A_STANDOUT = 65536
# A_UNDERLINE = 131072
# 15000 = black background, dark blue-green text
# 10000 = dark yellow background, black text
#  5000 = black
#  2000 = black
#  1000 = highlights show up black
#   100 = normal
#   500 = black and some underline

for num in 1...Curses.color_pairs # FIXME: things go to hell at about pair 256
  # for num in 1...([Curses::color_pairs, 256].min)
  COLOR_PAIR_HISTORY.push(num)
end

def get_color_pair_id(fg_code, bg_code)
  fg_id = if fg_code.nil?
            DEFAULT_COLOR_ID
          else
            get_color_id(fg_code)
          end
  bg_id = if bg_code.nil?
            DEFAULT_BACKGROUND_COLOR_ID
          else
            get_color_id(bg_code)
          end
  if (COLOR_PAIR_ID_LOOKUP[fg_id]) and (color_pair_id = COLOR_PAIR_ID_LOOKUP[fg_id][bg_id])
    color_pair_id
  else
    color_pair_id = COLOR_PAIR_HISTORY.shift
    COLOR_PAIR_ID_LOOKUP.each { |_w, x| x.delete_if { |_y, z| z == color_pair_id } }
    sleep 0.01
    Curses.init_pair(color_pair_id, fg_id, bg_id)
    COLOR_PAIR_ID_LOOKUP[fg_id] ||= {}
    COLOR_PAIR_ID_LOOKUP[fg_id][bg_id] = color_pair_id
    COLOR_PAIR_HISTORY.push(color_pair_id)
    color_pair_id
  end
end

# Implement support for basic readline-style kill and yank (cut and paste)
# commands.  Successive calls to delete_word, backspace_word, kill_forward, and
# kill_line will accumulate text into the kill_buffer as long as no other
# commands have changed the command buffer.  These commands call kill_before to
# reset the kill_buffer if the command buffer has changed, add the newly
# deleted text to the kill_buffer, and finally call kill_after to remember the
# state of the command buffer for next time.
kill_buffer   = ''
kill_original = ''
kill_last     = ''
kill_last_pos = 0
kill_before = proc {
  if kill_last != command_buffer || kill_last_pos != command_buffer_pos
    kill_buffer = ''
    kill_original = command_buffer
  end
}
kill_after = proc {
  kill_last = command_buffer.dup
  kill_last_pos = command_buffer_pos
}

fix_layout_number = proc { |str|
  str = str.gsub('lines', Curses.lines.to_s).gsub('cols', Curses.cols.to_s)
  begin
    proc { eval(str) }.call.to_i
  rescue StandardError
    warn $!
    warn $!.backtrace[0..1]
    0
  end
}

load_layout = proc { |layout_id|
  if (xml = LAYOUT[layout_id])
    old_windows = IndicatorWindow.list | TextWindow.list | CountdownWindow.list | ProgressWindow.list

    previous_indicator_handler = indicator_handler
    indicator_handler = {}

    previous_stream_handler = stream_handler
    stream_handler = {}

    previous_progress_handler = progress_handler
    progress_handler = {}

    previous_countdown_handler = countdown_handler
    progress_handler = {}

    xml.elements.each do |e|
      next unless e.name == 'window'

      height = fix_layout_number.call(e.attributes['height'])
      width = fix_layout_number.call(e.attributes['width'])
      top = fix_layout_number.call(e.attributes['top'])
      left = fix_layout_number.call(e.attributes['left'])
      if (height > 0) and (width > 0) and (top >= 0) and (left >= 0) and (top < Curses.lines) and (left < Curses.cols)
        if e.attributes['class'] == 'indicator'
          if e.attributes['value'] and (window = previous_indicator_handler[e.attributes['value']])
            previous_indicator_handler[e.attributes['value']] = nil
            old_windows.delete(window)
          else
            window = IndicatorWindow.new(height, width, top, left)
          end
          window.layout = [e.attributes['height'], e.attributes['width'], e.attributes['top'], e.attributes['left']]
          window.scrollok(false)
          window.label = e.attributes['label'] if e.attributes['label']
          if e.attributes['fg']
            window.fg = e.attributes['fg'].split(',').collect do |val|
              val == 'nil' ? nil : val
            end
          end
          if e.attributes['bg']
            window.bg = e.attributes['bg'].split(',').collect do |val|
              val == 'nil' ? nil : val
            end
          end
          indicator_handler[e.attributes['value']] = window if e.attributes['value']
          window.redraw
        elsif e.attributes['class'] == 'text'
          if width > 1
            if e.attributes['value'] and (window = previous_stream_handler[previous_stream_handler.keys.find do |key|
                                                                             e.attributes['value'].split(',').include?(key)
                                                                           end])
              previous_stream_handler[e.attributes['value']] = nil
              old_windows.delete(window)
            else
              window = TextWindow.new(height, width - 1, top, left)
              window.scrollbar = Curses::Window.new(window.maxy, 1, window.begy, window.begx + window.maxx)
            end
            window.layout = [e.attributes['height'], e.attributes['width'], e.attributes['top'],
                             e.attributes['left']]
            window.scrollok(true)
            window.max_buffer_size = e.attributes['buffer-size'] || 1000
            window.time_stamp = e.attributes['timestamp']
            e.attributes['value'].split(',').each do |str|
              stream_handler[str] = window
            end
          end
        elsif e.attributes['class'] == 'exp'
          stream_handler['exp'] = ExpWindow.new(height, width - 1, top, left)
        # elsif e.attributes['class'] == 'moonWindow'
        # 	stream_handler['moonWindow'] = PercWindow.new(height, width - 1, top, left)
        elsif e.attributes['class'] == 'percWindow'
          stream_handler['percWindow'] = PercWindow.new(height, width - 1, top, left)
        elsif e.attributes['class'] == 'countdown'
          if e.attributes['value'] and (window = previous_countdown_handler[e.attributes['value']])
            previous_countdown_handler[e.attributes['value']] = nil
            old_windows.delete(window)
          else
            window = CountdownWindow.new(height, width, top, left)
          end
          window.layout = [e.attributes['height'], e.attributes['width'], e.attributes['top'], e.attributes['left']]
          window.scrollok(false)
          window.label = e.attributes['label'] if e.attributes['label']
          if e.attributes['fg']
            window.fg = e.attributes['fg'].split(',').collect do |val|
              val == 'nil' ? nil : val
            end
          end
          if e.attributes['bg']
            window.bg = e.attributes['bg'].split(',').collect do |val|
              val == 'nil' ? nil : val
            end
          end
          countdown_handler[e.attributes['value']] = window if e.attributes['value']
          window.update
        elsif e.attributes['class'] == 'progress'
          if e.attributes['value'] and (window = previous_progress_handler[e.attributes['value']])
            previous_progress_handler[e.attributes['value']] = nil
            old_windows.delete(window)
          else
            window = ProgressWindow.new(height, width, top, left)
          end
          window.layout = [e.attributes['height'], e.attributes['width'], e.attributes['top'], e.attributes['left']]
          window.scrollok(false)
          window.label = e.attributes['label'] if e.attributes['label']
          if e.attributes['fg']
            window.fg = e.attributes['fg'].split(',').collect do |val|
              val == 'nil' ? nil : val
            end
          end
          if e.attributes['bg']
            window.bg = e.attributes['bg'].split(',').collect do |val|
              val == 'nil' ? nil : val
            end
          end
          progress_handler[e.attributes['value']] = window if e.attributes['value']
          window.redraw
        elsif e.attributes['class'] == 'command'
          command_window ||= Curses::Window.new(height, width, top, left)
          command_window_layout = [e.attributes['height'], e.attributes['width'], e.attributes['top'],
                                   e.attributes['left']]
          command_window.scrollok(false)
          command_window.keypad(true)
        end
      end
    end
    if (current_scroll_window = TextWindow.list[0])
      current_scroll_window.update_scrollbar
    end
    for window in old_windows
      IndicatorWindow.list.delete(window)
      TextWindow.list.delete(window)
      CountdownWindow.list.delete(window)
      ProgressWindow.list.delete(window)
      window.scrollbar.close if window.instance_of?(TextWindow)
      window.close
    end
    Curses.doupdate
  end
}

do_macro = nil

setup_key = proc { |xml, binding|
  if (key = xml.attributes['id'])
    if key =~ /^[0-9]+$/
      key = key.to_i
    elsif key.instance_of?(String) and (key.length == 1)
      nil
    else
      key = key_name[key]
    end
    if key
      if (macro = xml.attributes['macro'])
        binding[key] = proc { do_macro.call(macro) }
      elsif xml.attributes['action'] and (action = key_action[xml.attributes['action']])
        binding[key] = action
      else
        binding[key] ||= {}
        xml.elements.each do |e|
          setup_key.call(e, binding[key])
        end
      end
    end
  end
}

load_settings_file = proc { |reload|
  SETTINGS_LOCK.synchronize do
    HIGHLIGHT.clear
    File.open(SETTINGS_FILENAME) do |file|
      xml_doc = REXML::Document.new(file)
      xml_root = xml_doc.root
      xml_root.elements.each do |e|
        if e.name == 'highlight'
          begin
            r = Regexp.new(e.text)
          rescue StandardError
            r = nil
            warn e.to_s
            warn $!
          end
          HIGHLIGHT[r] = [e.attributes['fg'], e.attributes['bg'], e.attributes['ul']] if r
        elsif e.name == 'key'
          setup_key.call(e, key_binding)
        end
        # These are things that we ignore if we're doing a reload of the settings file
        unless reload
          if e.name == 'preset'
            PRESET[e.attributes['id']] = [e.attributes['fg'], e.attributes['bg']]
          elsif (e.name == 'layout') and (layout_id = e.attributes['id'])
            LAYOUT[layout_id] = e
          end
        end
      end
    end
  rescue StandardError
    $stdout.puts $!
    $stdout.puts $!.backtrace[0..1]
  end
}

command_window_put_ch = proc { |ch|
  if (command_buffer_pos - command_buffer_offset + 1) >= command_window.maxx
    command_window.setpos(0, 0)
    command_window.delch
    command_buffer_offset += 1
    command_window.setpos(0, command_buffer_pos - command_buffer_offset)
  end
  command_buffer.insert(command_buffer_pos, ch)
  command_buffer_pos += 1
  command_window.insch(ch)
  command_window.setpos(0, command_buffer_pos - command_buffer_offset)
}

do_macro = proc { |macro|
  # FIXME: gsub %whatever
  backslash = false
  at_pos = nil
  backfill = nil
  macro.split('').each_with_index do |ch, i|
    if backslash
      if ch == '\\'
        command_window_put_ch.call('\\')
      elsif ch == 'x'
        command_buffer.clear
        command_buffer_pos = 0
        command_buffer_offset = 0
        command_window.deleteln
        command_window.setpos(0, 0)
      elsif ch == 'r'
        at_pos = nil
        key_action['send_command'].call
      elsif ch == '@'
        command_window_put_ch.call('@')
      elsif ch == '?'
        backfill = i - 3
      end
      backslash = false
    elsif ch == '\\'
      backslash = true
    elsif ch == '@'
      at_pos = command_buffer_pos
    else
      command_window_put_ch.call(ch)
    end
  end
  if at_pos
    key_action['cursor_left'].call while at_pos < command_buffer_pos
    key_action['cursor_right'].call while at_pos > command_buffer_pos
  end
  command_window.noutrefresh
  if backfill
    command_window.setpos(0, backfill)
    command_buffer_pos = backfill
    backfill = nil
  end
  Curses.doupdate
}

key_action['resize'] = proc {
  # FIXME: re-word-wrap
  window = Window.new(0, 0, 0, 0)
  window.refresh
  window.close
  first_text_window = true
  for window in TextWindow.list.to_a
    window.resize(fix_layout_number.call(window.layout[0]), fix_layout_number.call(window.layout[1]) - 1)
    window.move(fix_layout_number.call(window.layout[2]), fix_layout_number.call(window.layout[3]))
    window.scrollbar.resize(window.maxy, 1)
    window.scrollbar.move(window.begy, window.begx + window.maxx)
    window.scroll(-window.maxy)
    window.scroll(window.maxy)
    window.clear_scrollbar
    if first_text_window
      window.update_scrollbar
      first_text_window = false
    end
    window.noutrefresh
  end
  for window in [IndicatorWindow.list.to_a, ProgressWindow.list.to_a, CountdownWindow.list.to_a].flatten
    window.resize(fix_layout_number.call(window.layout[0]), fix_layout_number.call(window.layout[1]))
    window.move(fix_layout_number.call(window.layout[2]), fix_layout_number.call(window.layout[3]))
    window.noutrefresh
  end
  if command_window
    command_window.resize(fix_layout_number.call(command_window_layout[0]), fix_layout_number.call(command_window_layout[1]))
    command_window.move(fix_layout_number.call(command_window_layout[2]), fix_layout_number.call(command_window_layout[3]))
    command_window.noutrefresh
  end
  Curses.doupdate
}

key_action['cursor_left'] = proc {
  if (command_buffer_offset > 0) and (command_buffer_pos - command_buffer_offset == 0)
    command_buffer_pos -= 1
    command_buffer_offset -= 1
    command_window.insch(command_buffer[command_buffer_pos])
  else
    command_buffer_pos = [command_buffer_pos - 1, 0].max
  end
  command_window.setpos(0, command_buffer_pos - command_buffer_offset)
  command_window.noutrefresh
  Curses.doupdate
}

key_action['cursor_right'] = proc {
  if ((command_buffer.length - command_buffer_offset) >= (command_window.maxx - 1)) and (command_buffer_pos - command_buffer_offset + 1) >= command_window.maxx
    if command_buffer_pos < command_buffer.length
      command_window.setpos(0, 0)
      command_window.delch
      command_buffer_offset += 1
      command_buffer_pos += 1
      command_window.setpos(0, command_buffer_pos - command_buffer_offset)
      command_window.insch(command_buffer[command_buffer_pos]) unless command_buffer_pos >= command_buffer.length
    end
  else
    command_buffer_pos = [command_buffer_pos + 1, command_buffer.length].min
    command_window.setpos(0, command_buffer_pos - command_buffer_offset)
  end
  command_window.noutrefresh
  Curses.doupdate
}

key_action['cursor_word_left'] = proc {
  if command_buffer_pos > 0
    new_pos = if (m = command_buffer[0...(command_buffer_pos - 1)].match(/.*(\w[^\w\s]|\W\w|\s\S)/))
                m.begin(1) + 1
              else
                0
              end
    if command_buffer_offset > new_pos
      command_window.setpos(0, 0)
      command_buffer[new_pos, (command_buffer_offset - new_pos)].split('').reverse.each do |ch|
        command_window.insch(ch)
      end
      command_buffer_pos = new_pos
      command_buffer_offset = new_pos
    else
      command_buffer_pos = new_pos
    end
    command_window.setpos(0, command_buffer_pos - command_buffer_offset)
    command_window.noutrefresh
    Curses.doupdate
  end
}

key_action['cursor_word_right'] = proc {
  if command_buffer_pos < command_buffer.length
    new_pos = if (m = command_buffer[command_buffer_pos..-1].match(/\w[^\w\s]|\W\w|\s\S/))
                command_buffer_pos + m.begin(0) + 1
              else
                command_buffer.length
              end
    overflow = new_pos - command_window.maxx - command_buffer_offset + 1
    if overflow > 0
      command_window.setpos(0, 0)
      overflow.times do
        command_window.delch
        command_buffer_offset += 1
      end
      command_window.setpos(0, command_window.maxx - overflow)
      command_window.addstr command_buffer[(command_window.maxx - overflow + command_buffer_offset), overflow]
    end
    command_buffer_pos = new_pos
    command_window.setpos(0, command_buffer_pos - command_buffer_offset)
    command_window.noutrefresh
    Curses.doupdate
  end
}

key_action['cursor_home'] = proc {
  command_buffer_pos = 0
  command_window.setpos(0, 0)
  for num in 1..command_buffer_offset
    begin
      command_window.insch(command_buffer[command_buffer_offset - num])
    rescue StandardError
      File.open('profanity.log', 'a') do |f|
        f.puts "command_buffer: #{command_buffer.inspect}"
        f.puts "command_buffer_offset: #{command_buffer_offset.inspect}"
        f.puts "num: #{num.inspect}"
        f.puts $!
        f.puts $!.backtrace[0...4]
      end
      exit
    end
  end
  command_buffer_offset = 0
  command_window.noutrefresh
  Curses.doupdate
}

key_action['cursor_end'] = proc {
  if command_buffer.length < (command_window.maxx - 1)
    command_buffer_pos = command_buffer.length
    command_window.setpos(0, command_buffer_pos)
  else
    scroll_left_num = command_buffer.length - command_window.maxx + 1 - command_buffer_offset
    command_window.setpos(0, 0)
    scroll_left_num.times do
      command_window.delch
      command_buffer_offset += 1
    end
    command_buffer_pos = command_buffer_offset + command_window.maxx - 1 - scroll_left_num
    command_window.setpos(0, command_buffer_pos - command_buffer_offset)
    scroll_left_num.times do
      command_window.addch(command_buffer[command_buffer_pos])
      command_buffer_pos += 1
    end
  end
  command_window.noutrefresh
  Curses.doupdate
}

key_action['cursor_backspace'] = proc {
  if command_buffer_pos > 0
    command_buffer_pos -= 1
    command_buffer = if command_buffer_pos == 0
                       command_buffer[(command_buffer_pos + 1)..-1]
                     else
                       command_buffer[0..(command_buffer_pos - 1)] + command_buffer[(command_buffer_pos + 1)..-1]
                     end
    command_window.setpos(0, command_buffer_pos - command_buffer_offset)
    command_window.delch
    if (command_buffer.length - command_buffer_offset + 1) > command_window.maxx
      command_window.setpos(0, command_window.maxx - 1)
      command_window.addch command_buffer[command_window.maxx - command_buffer_offset - 1]
      command_window.setpos(0, command_buffer_pos - command_buffer_offset)
    end
    command_window.noutrefresh
    Curses.doupdate
  end
}

class String
  def alnum?
    !!match(/^[[:alnum:]]+$/)
  end

  def digits?
    !!match(/^[[:digit:]]+$/)
  end

  def punct?
    !!match(/^[[:punct:]]+$/)
  end

  def space?
    !!match(/^[[:space:]]+$/)
  end
end

key_action['cursor_delete'] = proc {
  if (command_buffer.length > 0) and (command_buffer_pos < command_buffer.length)
    if command_buffer_pos == 0
      command_buffer = command_buffer[(command_buffer_pos + 1)..-1]
    elsif command_buffer_pos < command_buffer.length
      command_buffer = command_buffer[0..(command_buffer_pos - 1)] + command_buffer[(command_buffer_pos + 1)..-1]
    end
    command_window.delch
    if (command_buffer.length - command_buffer_offset + 1) > command_window.maxx
      command_window.setpos(0, command_window.maxx - 1)
      command_window.addch command_buffer[command_window.maxx - command_buffer_offset - 1]
      command_window.setpos(0, command_buffer_pos - command_buffer_offset)
    end
    command_window.noutrefresh
    Curses.doupdate
  end
}

key_action['cursor_backspace_word'] = proc {
  num_deleted = 0
  deleted_alnum = false
  deleted_nonspace = false
  while command_buffer_pos > 0
    next_char = command_buffer[command_buffer_pos - 1]
    unless num_deleted == 0 || (!deleted_alnum && next_char.punct?) || (!deleted_nonspace && next_char.space?) || next_char.alnum?
      break
    end

    deleted_alnum ||= next_char.alnum?
    deleted_nonspace = !next_char.space?
    num_deleted += 1
    kill_before.call
    kill_buffer = next_char + kill_buffer
    key_action['cursor_backspace'].call
    kill_after.call

  end
}

key_action['cursor_delete_word'] = proc {
  num_deleted = 0
  deleted_alnum = false
  deleted_nonspace = false
  while command_buffer_pos < command_buffer.length
    next_char = command_buffer[command_buffer_pos]
    unless num_deleted == 0 || (!deleted_alnum && next_char.punct?) || (!deleted_nonspace && next_char.space?) || next_char.alnum?
      break
    end

    deleted_alnum ||= next_char.alnum?
    deleted_nonspace = !next_char.space?
    num_deleted += 1
    kill_before.call
    kill_buffer += next_char
    key_action['cursor_delete'].call
    kill_after.call

  end
}

key_action['cursor_kill_forward'] = proc {
  if command_buffer_pos < command_buffer.length
    kill_before.call
    if command_buffer_pos == 0
      kill_buffer += command_buffer
      command_buffer = ''
    else
      kill_buffer += command_buffer[command_buffer_pos..-1]
      command_buffer = command_buffer[0..(command_buffer_pos - 1)]
    end
    kill_after.calll

    command_window.clrtoeol
    command_window.noutrefresh
    Curses.doupdate
  end
}

key_action['cursor_kill_line'] = proc {
  if command_buffer.length != 0
    kill_before.call
    kill_buffer = kill_original
    command_buffer = ''
    command_buffer_pos = 0
    command_buffer_offset = 0
    kill_after.call
    command_window.setpos(0, 0)
    command_window.clrtoeol
    command_window.noutrefresh
    Curses.doupdate
  end
}

key_action['cursor_yank'] = proc {
  kill_buffer.each_char { |c| command_window_put_ch.call(c) }
}

key_action['switch_current_window'] = proc {
  if (current_scroll_window = TextWindow.list[0])
    current_scroll_window.clear_scrollbar
  end
  TextWindow.list.push(TextWindow.list.shift)
  if (current_scroll_window = TextWindow.list[0])
    current_scroll_window.update_scrollbar
  end
  command_window.noutrefresh
  Curses.doupdate
}

key_action['scroll_current_window_up_one'] = proc {
  if (current_scroll_window = TextWindow.list[0])
    current_scroll_window.scroll(-1)
  end
  command_window.noutrefresh
  Curses.doupdate
}

key_action['scroll_current_window_down_one'] = proc {
  if (current_scroll_window = TextWindow.list[0])
    current_scroll_window.scroll(1)
  end
  command_window.noutrefresh
  Curses.doupdate
}

key_action['scroll_current_window_up_page'] = proc {
  if (current_scroll_window = TextWindow.list[0])
    current_scroll_window.scroll(0 - current_scroll_window.maxy + 1)
  end
  command_window.noutrefresh
  Curses.doupdate
}

key_action['scroll_current_window_down_page'] = proc {
  if (current_scroll_window = TextWindow.list[0])
    current_scroll_window.scroll(current_scroll_window.maxy - 1)
  end
  command_window.noutrefresh
  Curses.doupdate
}

key_action['scroll_current_window_bottom'] = proc {
  if (current_scroll_window = TextWindow.list[0])
    current_scroll_window.scroll(current_scroll_window.max_buffer_size)
  end
  command_window.noutrefresh
  Curses.doupdate
}

key_action['previous_command'] = proc {
  if command_history_pos < (command_history.length - 1)
    command_history[command_history_pos] = command_buffer.dup
    command_history_pos += 1
    command_buffer = command_history[command_history_pos].dup
    command_buffer_offset = [(command_buffer.length - command_window.maxx + 1), 0].max
    command_buffer_pos = command_buffer.length
    command_window.setpos(0, 0)
    command_window.deleteln
    command_window.addstr command_buffer[command_buffer_offset, (command_buffer.length - command_buffer_offset)]
    command_window.setpos(0, command_buffer_pos - command_buffer_offset)
    command_window.noutrefresh
    Curses.doupdate
  end
}

key_action['next_command'] = proc {
  if command_history_pos == 0
    unless command_buffer.empty?
      command_history[command_history_pos] = command_buffer.dup
      command_history.unshift String.new
      command_buffer.clear
      command_window.deleteln
      command_buffer_pos = 0
      command_buffer_offset = 0
      command_window.setpos(0, 0)
      command_window.noutrefresh
      Curses.doupdate
    end
  else
    command_history[command_history_pos] = command_buffer.dup
    command_history_pos -= 1
    command_buffer = command_history[command_history_pos].dup
    command_buffer_offset = [(command_buffer.length - command_window.maxx + 1), 0].max
    command_buffer_pos = command_buffer.length
    command_window.setpos(0, 0)
    command_window.deleteln
    command_window.addstr command_buffer[command_buffer_offset, (command_buffer.length - command_buffer_offset)]
    command_window.setpos(0, command_buffer_pos - command_buffer_offset)
    command_window.noutrefresh
    Curses.doupdate
  end
}

key_action['switch_arrow_mode'] = proc {
  if key_binding[Curses::KEY_UP] == key_action['previous_command']
    key_binding[Curses::KEY_UP] = key_action['scroll_current_window_up_page']
    key_binding[Curses::KEY_DOWN] = key_action['scroll_current_window_down_page']
  else
    key_binding[Curses::KEY_UP] = key_action['previous_command']
    key_binding[Curses::KEY_DOWN] = key_action['next_command']
  end
}

key_action['send_command'] = proc {
  cmd = command_buffer.dup
  command_buffer.clear
  command_buffer_pos = 0
  command_buffer_offset = 0
  need_prompt = false
  if (window = stream_handler['main'])
    add_prompt(window, prompt_text, cmd)
  end
  command_window.deleteln
  command_window.setpos(0, 0)
  command_window.noutrefresh
  Curses.doupdate
  command_history_pos = 0
  # Remember all digit commands because they are likely spells for voodoo.lic
  if (cmd.length >= min_cmd_length_for_history || cmd.digits?) and (cmd != command_history[1])
    if command_history[0].nil? or command_history[0].empty?
      command_history[0] = cmd
    else
      command_history.unshift cmd
    end
    command_history.unshift String.new
  end
  if cmd =~ /^\.quit/
    exit
  elsif cmd =~ /^\.key/i
    window = stream_handler['main']
    window.add_string('* ')
    window.add_string('* Waiting for key press...')
    command_window.noutrefresh
    Curses.doupdate
    window.add_string("* Detected keycode: #{command_window.getch}")
    window.add_string('* ')
    Curses.doupdate
  elsif cmd =~ /^\.copy/
    # fixme
  elsif cmd =~ /^\.fixcolor/i
    if CUSTOM_COLORS
      COLOR_ID_LOOKUP.each do |code, id|
        Curses.init_color(id, ((code[0..1].to_s.hex / 255.0) * 1000).round, ((code[2..3].to_s.hex / 255.0) * 1000).round, ((code[4..5].to_s.hex / 255.0) * 1000).round)
      end
    end
  elsif cmd =~ /^\.resync/i
    skip_server_time_offset = false
  elsif cmd =~ /^\.reload/i
    load_settings_file.call(true)
  elsif cmd =~ /^\.layout\s+(.+)/
    load_layout.call(Regexp.last_match(1))
    key_action['resize'].call
  elsif cmd =~ /^\.arrow/i
    key_action['switch_arrow_mode'].call
  elsif cmd =~ /^\.e (.*)/
    eval(cmd.sub(/^\.e /, ''))
  else
    server.puts cmd.sub(/^\./, ';')
  end
}

key_action['send_last_command'] = proc {
  if (cmd = command_history[1])
    if (window = stream_handler['main'])
      add_prompt(window, prompt_text, cmd)
      # window.add_string(">#{cmd}", [ h={ :start => 0, :end => (cmd.length + 1), :fg => '555555' } ])
      command_window.noutrefresh
      Curses.doupdate
    end
    if cmd =~ /^\.quit/i
      exit
    elsif cmd =~ /^\.fixcolor/i
      if CUSTOM_COLORS
        COLOR_ID_LOOKUP.each do |code, id|
          Curses.init_color(id, ((code[0..1].to_s.hex / 255.0) * 1000).round, ((code[2..3].to_s.hex / 255.0) * 1000).round, ((code[4..5].to_s.hex / 255.0) * 1000).round)
        end
      end
    elsif cmd =~ /^\.resync/i
      skip_server_time_offset = false
    elsif cmd =~ /^\.arrow/i
      key_action['switch_arrow_mode'].call
    elsif cmd =~ /^\.e (.*)/
      eval(cmd.sub(/^\.e /, ''))
    end
  end
}

key_action['send_second_last_command'] = proc {
  if (cmd = command_history[2])
    if (window = stream_handler['main'])
      add_prompt(window, prompt_text, cmd)
      # window.add_string(">#{cmd}", [ h={ :start => 0, :end => (cmd.length + 1), :fg => '555555' } ])
      command_window.noutrefresh
      Curses.doupdate
    end
    if cmd =~ /^\.quit/i
      exit
    elsif cmd =~ /^\.fixcolor/i
      if CUSTOM_COLORS
        COLOR_ID_LOOKUP.each do |code, id|
          Curses.init_color(id, ((code[0..1].to_s.hex / 255.0) * 1000).round, ((code[2..3].to_s.hex / 255.0) * 1000).round, ((code[4..5].to_s.hex / 255.0) * 1000).round)
        end
      end
    elsif cmd =~ /^\.resync/i
      skip_server_time_offset = false
    elsif cmd =~ /^\.arrow/i
      key_action['switch_arrow_mode'].call
    elsif cmd =~ /^\.e (.*)/
      eval(cmd.sub(/^\.e /, ''))
    else
      server.puts cmd.sub(/^\./, ';')
    end
  end
}

new_stun = proc { |seconds|
  if (window = countdown_handler['stunned'])
    temp_stun_end = Time.now.to_f - $server_time_offset.to_f + seconds.to_f
    window.end_time = temp_stun_end
    window.update
    # need_update = true
    Thread.new do
      while (countdown_handler['stunned'].end_time == temp_stun_end) and (countdown_handler['stunned'].value > 0)
        sleep 0.15
        if countdown_handler['stunned'].update
          command_window.noutrefresh
          Curses.doupdate
        end
      end
    end
  end
}

load_settings_file.call(false)
load_layout.call('default')

TextWindow.list.each { |w| w.maxy.times { w.add_string "\n" } }

server = TCPSocket.open('127.0.0.1', PORT)

Thread.new do
  sleep 15
  skip_server_time_offset = false
end

Thread.new do
  line = nil
  need_update = false
  line_colors = []
  open_monsterbold = []
  open_preset = []
  open_style = nil
  open_color = []
  current_stream = nil
  bold_next_line = false
  emptycount = 0

  handle_game_text = proc { |text|
    for escapable in xml_escape_list.keys
      search_pos = 0
      while (pos = text.index(escapable, search_pos))
        text = text.sub(escapable, xml_escape_list[escapable])
        line_colors.each do |h|
          h[:start] -= (escapable.length - 1) if h[:start] > pos
          h[:end] -= (escapable.length - 1) if h[:end] > pos
        end
        open_style[:start] -= (escapable.length - 1) if open_style and (open_style[:start] > pos)
      end
    end

    if text =~ /^\[\w+: \*\*\*STATUS\*\*\*\s(?!\d+).*/
      note = text.gsub(/(\[|\]|\*\*\*STATUS\*\*\* )/, '')
    elsif text =~ /You sense nothing wrong with (\w+)/
      note = "#{Regexp.last_match(1)} is all healthy."
    elsif text =~ /You believe you've learned something significant about (\w+\s?\w*)!$/
      note = "Almanac: #{Regexp.last_match(1)}"
    elsif text =~ %r{Tarantula successfully sacrificed (\d+)/34 of (\w+\s?\w*) at}
      note = "Tarantula: #{Regexp.last_match(2)} #{Regexp.last_match(1)}/34"
    elsif text =~ /contains a complete description of the (.*) spell/
      note = "Scroll spell: #{Regexp.last_match(1)}"
    elsif text =~ /^You raise the bead up, and a black glow surrounds it/
      note = "Focus effect started."
    elsif text =~ /^The glow slowly fades away from around you/
      note = "Focus effect ended."
    elsif text =~ /^You ask, "Is anyone hunting in here\?"/
      next
    elsif text.match(/^\[combat-trainer\]>loot/)
      next
    end

    if note
      line_colors = [{
        start: 0,
        end: note.length,
        fg: PRESET['monsterbold'][0],
        bg: PRESET['monsterbold'][1]
      }]
      stream_handler['familiar'].add_string(note, line_colors)
      need_update = true
    end

    if text =~ /^\[.*?\]>/
      need_prompt = false
    elsif text =~ /^\s*You are stunned for ([0-9]+) rounds?/
      new_stun.call(Regexp.last_match(1).to_i * 5)
    # elsif text =~ /^Deep and resonating, you feel the chant that falls from your lips instill within you with the strength of your faith\.  You crouch beside [A-Z][a-z]+ and gently lift (?:he|she|him|her) into your arms, your muscles swelling with the power of your deity, and cradle (?:him|her) close to your chest\.  Strength and life momentarily seep from your limbs, causing them to feel laden and heavy, and you are overcome with a sudden weakness\.  With a sigh, you are able to lay [A-Z][a-z]+ back down\.$|^Moisture beads upon your skin and you feel your eyes cloud over with the darkness of a rising storm\.  Power builds upon the air and when you utter the last syllable of your spell thunder rumbles from your lips\.  The sound ripples upon the air, and colling with [A-Z][a-z&apos;]+ prone form and a brilliant flash transfers the spiritual energy between you\.$|^Lifting your finger, you begin to chant and draw a series of conjoined circles in the air\.  Each circle turns to mist and takes on a different hue - white, blue, black, red, and green\.  As the last ring is completed, you spread your fingers and gently allow your tips to touch each color before pushing the misty creation towards [A-Z][a-z]+\.  A shock of energy courses through your body as the mist seeps into [A-Z][a-z&apos;]+ chest and life is slowly returned to (?:his|her) body\.$|^Crouching beside the prone form of [A-Z][a-z]+, you softly issue the last syllable of your chant\.  Breathing deeply, you take in the scents around you and let the feel of your surroundings infuse you\.  With only your gaze, you track the area and recreate the circumstances of [A-Z][a-z&apos;]+ within your mind\.  Touching [A-Z][a-z]+, you follow the lines of the web that holds (?:his|her) soul in place and force it back into (?:his|her) body\.  Raw energy courses through you and you feel your sense of justice and vengeance filling [A-Z][a-z]+ with life\.$|^Murmuring softly, you call upon your connection with the Destroyer,? and feel your words twist into an alien, spidery chant\.  Dark shadows laced with crimson swirl before your eyes and at your forceful command sink into the chest of [A-Z][a-z]+\.  The transference of energy is swift and immediate as you bind [A-Z][a-z]+ back into (?:his|her) body\.$|^Rich and lively, the scent of wild flowers suddenly fills the air as you finish your chant, and you feel alive with the energy of spring\.  With renewal at your fingertips, you gently touch [A-Z][a-z]+ on the brow and revel in the sweet rush of energy that passes through you into (?:him|her|his)\.$|^Breathing slowly, you extend your senses towards the world around you and draw into you the very essence of nature\.  You shift your gaze towards [A-z][a-z]+ and carefully release the energy you&apos;ve drawn into yourself towards (?:him|her)\.  A rush of energy briefly flows between the two of you as you feel life slowly return to (?:him|her)\.$|^Your surroundings grow dim\.\.\.you lapse into a state of awareness only, unable to do anything\.\.\.$|^Murmuring softly, a mournful chant slips from your lips and you feel welts appear upon your wrists\.  Dipping them briefly, you smear the crimson liquid the leaks from these sudden wounds in a thin line down [A-Z][a-z&apos;]+ face\.  Tingling with each second that your skin touches (?:his|hers), you feel the transference of your raw energy pass into [A-Z][a-z]+ and momentarily reel with the pain of its release\.  Slowly, the wounds on your wrists heal, though a lingering throb remains\.$|^Emptying all breathe from your body, you slowly still yourself and close your eyes\.  You reach out with all of your senses and feel a film shift across your vision\.  Opening your eyes, you gaze through a white haze and find images of [A-Z][a-z]+ floating above his prone form\.  Acts of [A-Z][a-z]&apos;s? past, present, and future play out before your clouded vision\.  With conviction and faith, you pluck a future image of [A-Z][a-z]+ from the air and coax (?:he|she|his|her) back into (?:he|she|his|her) body\.  Slowly, the film slips from your eyes and images fade away\.$|^Thin at first, a fine layer of rime tickles your hands and fingertips\.  The hoarfrost smoothly glides between you and [A-Z][a-z]+, turning to a light powder as it traverses the space\.  The white substance clings to [A-Z][a-z]+&apos;s? eyelashes and cheeks for a moment before it becomes charged with spiritual power, then it slowly melts away\.$|^As you begin to chant,? you notice the scent of dry, dusty parchment and feel a cool mist cling to your skin somewhere near your feet\.  You sense the ethereal tendrils of the mist as they coil about your body and notice that the world turns to a yellowish hue as the mist settles about your head\.  Focusing on [A-Z][a-z]+, you feel the transfer of energy pass between you as you return (?:him|her) to life\.$|^Wrapped in an aura of chill, you close your eyes and softly begin to chant\.  As the cold air that surrounds you condenses you feel it slowly ripple outward in waves that turn the breath of those nearby into a fine mist\.  This mist swiftly moves to encompass you and you feel a pair of wings arc over your back\.  With the last words of your chant, you open your eyes and watch as foggy wings rise above you and gently brush against [A-Z][a-z]+\.  As they dissipate in a cold rush against [A-Z][a-z]+, you feel a surge of power spill forth from you and into (?:him|her)\.$|^As .*? begins to chant, your spirit is drawn closer to your body by the scent of dusty, dry parchment\.  Topaz tendrils coil about .*?, and you feel an ancient presence demand that you return to your body\.  All at once .*? focuses upon you and you feel a surge of energy bind you back into your now-living body\.$/
    #   # raise dead stun
    #   new_stun.call(30.6)
    elsif text =~ /^Just as you think the falling will never end, you crash through an ethereal barrier which bursts into a dazzling kaleidoscope of color!  Your sensation of falling turns to dizziness and you feel unusually heavy for a moment\.  Everything seems to stop for a prolonged second and then WHUMP!!!/
      # Shadow Valley exit stun
      new_stun.call(16.2)
    # elsif text =~ /^You have.*?(?:case of uncontrollable convulsions|case of sporadic convulsions|strange case of muscle twitching)/
    #   # nsys wound will be correctly set by xml, dont set the scar using health verb output
    #   skip_nsys = true
    elsif text =~ /^You glance down at your empty hands\./
      if (window = indicator_handler['right'])
        window.clear
        window.label = 'Empty'
        need_update = true
      end
      if (window = indicator_handler['left'])
        window.clear
        window.label = 'Empty'
        need_update = true
      end
    # elsif skip_nsys
    #   skip_nsys = false
    elsif (window = indicator_handler['nsys'])
      if text =~ /^You have.*? very difficult time with muscle control/
        need_update = true if window.update(3)
      elsif text =~ /^You have.*? constant muscle spasms/
        need_update = true if window.update(2)
      elsif text =~ /^You have.*? developed slurred speech/
        need_update = true if window.update(1)
      end
    end

    if open_style
      h = open_style.dup
      h[:end] = text.length
      line_colors.push(h)
      open_style[:start] = 0
    end
    for oc in open_color
      ocd = oc.dup
      ocd[:end] = text.length
      line_colors.push(ocd)
      oc[:start] = 0
    end

    if current_stream.nil? or stream_handler[current_stream] or (current_stream =~ /^(?:death|logons|thoughts|voln|familiar|assess|ooc|shopWindow|combat|moonWindow|atmospherics)$/)
      SETTINGS_LOCK.synchronize do
        HIGHLIGHT.each_pair do |regex, colors|
          pos = 0
          while (match_data = text.match(regex, pos))
            h = {
              start: match_data.begin(0),
              end: match_data.end(0),
              fg: colors[0],
              bg: colors[1],
              ul: colors[2]
            }
            line_colors.push(h)
            pos = match_data.end(0)
          end
        end
      end
    end

    unless text.empty?
      if current_stream

        if current_stream == 'combat' && text.match(combat_gag_regexp)
          File.write("combatgaglog.txt", line.inspect + "\n", mode: "a")
          next
        end

        if current_stream == 'thoughts' && (text =~ /^\[.+?\]-[A-z]+:[A-Z][a-z]+: "|^\[server\]: /)
          current_stream = 'lnet'
        end

        if (window = stream_handler[current_stream])
          if current_stream == 'death'
            # FIXME: has been vaporized!
            # fixme: ~ off to a rough start
            if text =~ /^\s\*\s(?:A fiery phoenix soars into the heavens as\s)?([A-Z][a-z]+)(?: was just struck down.*| just disintegrated!| was lost to the Plane of Exile!|'s spirit arises from the ashes of death.)/
              name = Regexp.last_match(1)
              text = "#{name} #{Time.now.strftime('%l:%M%P').sub(/^0/, '')}"
              line_colors.each do |h|
                h[:start] -= 3
                h[:end] = [h[:end], name.length].min
              end
              line_colors.delete_if { |hash| hash[:start] >= hash[:end] }
              h = {
                start: (name.length + 1),
                end: text.length,
                fg: 'ff0000'
              }
              line_colors.push(h)
            end
          elsif current_stream == 'logons'
            foo = { 'joins the adventure with little fanfare.' => '007700',
                    'just sauntered into the adventure with an annoying tune on his lips.' => '007700', 'just wandered into another adventure.' => '007700', 'just limped in for another adventure.' => '007700', 'snuck out of the shadow he was hiding in.' => '007700', 'joins the adventure with a gleam in her eye.' => '007700', 'joins the adventure with a gleam in his eye.' => '007700', 'comes out from within the shadows with renewed vigor.' => '007700', 'just crawled into the adventure.' => '007700', 'has woken up in search of new ale!' => '007700', 'just popped into existance.' => '007700', 'has joined the adventure after escaping another.' => '007700', 'joins the adventure.' => '007700', 'returns home from a hard day of adventuring.' => '777700', 'has left to contemplate the life of a warrior.' => '777700', 'just sauntered off-duty to get some rest.' => '777700', 'departs from the adventure with little fanfare.' => '777700', 'limped away from the adventure for now.' => '777700', 'thankfully just returned home to work on a new tune.' => '777700', 'fades swiftly into the shadows.' => '777700', 'retires from the adventure for now.' => '777700', 'just found a shadow to hide out in.' => '777700', 'quietly departs the adventure.' => '777700', 'has disconnected.' => 'aa7733' }
            if text =~ /^\s\*\s([A-Z][a-z]+) (#{foo.keys.join('|')})/
              name = Regexp.last_match(1)
              logon_type = Regexp.last_match(2)
              text = "#{name} #{Time.now.strftime('%l:%M%P').sub(/^0/, '')}"
              line_colors.each do |hash|
                hash[:start] -= 3
                hash[:end] = [h[:end], name.length].min
              end
              line_colors.delete_if { |hash| hash[:start] >= hash[:end] }
              h = {
                start: (name.length + 1),
                end: text.length,
                fg: foo[logon_type]
              }
              line_colors.push(h)
            end
          elsif current_stream == 'exp'
            window = stream_handler['exp']
          elsif current_stream == 'percWindow'
            window = stream_handler['percWindow']
            all_spells = {
              'Abandoned Heart'            => 'ABAN',
              'Absolution'                 => 'Absolution',
              'Acid Splash'                => 'ACS',
              'Aegis of Granite'           => 'AEG',
              'Aesandry Darlaeth'          => 'AD',
              'Aesrela Everild'            => 'AE',
              'Aether Cloak'               => 'AC',
              'Aether Wolves'              => 'AEWO',
              'Aethrolysis'                => 'Aethrolysis',
              'Avren Aevareae'             => 'AVA',
              'Aggressive Stance'          => 'AGS',
              'Air Bubble'                 => 'AB',
              'Air Lash'                   => 'ALA',
              "Alamhif's Gift"             => 'AG',
              "Albreda's Balm"             => 'ALB',
              "Anther's Call"              => 'ANC',
              'Anti-Stun'                  => 'AS',
              "Arbiter's Stylus"           => 'ARS',
              'Arc Light'                  => 'AL',
              "Artificer's Eye"            => 'ART',
              'Aspects of the All-God'     => 'ALL',
              "Aspirant's Aegis"           => 'AA',
              'Athleticism'                => 'Athleticism',
              'Aura Sight'                 => 'AUS',
              'Aura of Tongues'            => 'AOT',
              'Auspice'                    => 'Auspice',
              'Awaken'                     => 'Awaken',
              'Awaken Forest'              => 'AF',
              'Banner of Truce'            => 'BOT',
              'Bear Strength'              => 'BES',
              'Beckon the Naga'            => 'BTN',
              'Benediction'                => 'Benediction',
              'Blend'                      => 'Blend',
              'Bless'                      => 'Bless',
              'Blessing of the Fae'        => 'BOTF',
              'Bloodthorns'                => 'Bloodthorns',
              'Blood Burst'                => 'BLB',
              'Blood Staunching'           => 'BS',
              'Blufmor Garaen'             => 'BG',
              'Blur'                       => 'Blur',
              'Bond Armaments'             => 'BA',
              "Braun's Conjecture"         => 'BC',
              'Breath of Storms'           => 'BOS',
              'Burden'                     => 'Burden',
              'Burn'                       => 'Burn',
              "Butcher's Eye"              => 'BUE',
              'Cage of Light'              => 'CoL',
              'Calcified Hide'             => 'CH',
              'Call from Beyond'           => 'CFB',
              'Calm'                       => 'Calm',
              'Caress of the Sun'          => 'CARE',
              'Carrion Call'               => 'CAC',
              'Centering'                  => 'Centering',
              'Chain Lightning'            => 'CL',
              'Cheetah Swiftness'          => 'CS',
              'Chill Spirit'               => 'CHS',
              'Circle of Sympathy'         => 'COS',
              'Clarity'                    => 'Clarity',
              'Claws of the Cougar'        => 'COTC',
              'Clear Vision'               => 'CV',
              'Compel'                     => 'Compel',
              'Compost'                    => 'Compost',
              'Consume Flesh'              => 'CF',
              'Contingency'                => 'Contingency',
              'Courage'                    => 'CO',
              'Crystal Dart'               => 'CRD',
              "Crusader's Challenge"       => 'CRC',
              'Cure Disease'               => 'CD',
              'Curse of the Wilds'         => 'COTW',
              'Curse of Zachriedek'        => 'COZ',
              "Damaris' Lullaby"           => 'DALU',
              'Dazzle'                     => 'Dazzle',
              'Deadfall'                   => 'DF',
              "Demrris' Resolve"           => 'DMRS',
              "Desert's Maelstrom"         => 'DEMA',
              'Destiny Cipher'             => 'DC',
              'Devitalize'                 => 'DEVI',
              'Devolve'                    => 'DE',
              'Devour'                     => 'Devour',
              'Dispel'                     => 'Dispel',
              'Distant Gaze'               => 'DG',
              'Dinazen Olkar'              => 'DO',
              'Divine Armor'               => 'DA',
              'Divine Guidance'            => 'DIG',
              'Divine Radiance'            => 'DR',
              "Dragon's Breath"            => 'DB',
              'Drought'                    => 'Drought',
              'Drums of the Snake'         => 'DRUM',
              'Ease Burden'                => 'EASE',
              "Eagle's Cry"                => 'EC',
              'Earth Meld'                 => 'EM',
              'Echoes of Aether'           => 'ECHO',
              "Eillie's Cry"               => 'ECRY',
              'Elision'                    => 'ELI',
              'Electrostatic Eddy'         => 'EE',
              "Emuin's Candlelight"        => 'EMC',
              'Enrichment'                 => 'ENRICH',
              'Essence of Yew'             => 'EY',
              'Ethereal Fissure'           => 'ETF',
              'Ethereal Shield'            => 'ES',
              'Eye of Kertigen'            => 'EYE',
              'Eyes of the Blind'          => 'EOTB',
              "Eylhaar's Feast"            => 'EF',
              "Faenella's Grace"           => 'FAE',
              'Failure of the Forge'       => 'FOTF',
              'Fire Ball'                  => 'FB',
              'Fire Rain'                  => 'FR',
              'Fire Shards'                => 'FS',
              'Fire of Ushnish'            => 'FOU',
              'Fists of Faenella'          => 'FF',
              'Finesse'                    => 'FIN',
              'Fluoresce'                  => 'Fluoresce',
              'Flush Poisons'              => 'FP',
              'Focus Moonbeam'             => 'FM',
              "Footman's Strike"           => 'FST',
              "Forestwalker's Boon"        => 'FWB',
              'Fortress of Ice'            => 'FOI',
              'Fountain of Creation'       => 'FOC',
              'Frostbite'                  => 'frostbite',
              'Frost Scythe'               => 'FRS',
              'Gam Irnan'                  => 'GI',
              'Gauge Flow'                 => 'GAF',
              'Gar Zeng'                   => 'GZ',
              'Geyser'                     => 'Geyser',
              'Ghost Shroud'               => 'GHS',
              'Ghoulflesh'                 => 'Ghoulflesh',
              'Gift of Life'               => 'GOL',
              "Glythtide's Gift"           => 'GG',
              "Glythtide's Joy"            => 'GJ',
              'Grizzly Claws'              => 'GRIZ',
              'Grounding Field'            => 'GF',
              'Guardian Spirit'            => 'GS',
              'Halo'                       => 'HALO',
              'Halt'                       => 'Halt',
              'Hand of Tenemlor'           => 'HOT',
              'Hands of Justice'           => 'HOJ',
              'Hands of Lirisa'            => 'HOL',
              "Harawep's Bonds"            => 'HB',
              'Harm Evil'                  => 'HE',
              'Harm Horde'                 => 'HH',
              'Harmony'                    => 'Harmony',
              'Heal'                       => 'Heal',
              'Heal Scars'                 => 'HS',
              'Heal Wounds'                => 'HW',
              'Heart Link'                 => 'HL',
              'Heighten Pain'              => 'HP',
              'Heroic Strength'            => 'HES',
              "Hodierna's Lilt"            => 'HODI',
              'Holy Warrior'               => 'HOW',
              'Horn of the Black Unicorn'  => 'HORN',
              "Huldah's Pall"              => 'HULP',
              'Hydra Hex'                  => 'HYH',
              'Ice Patch'                  => 'IP',
              'Icutu Zaharenela'           => 'IZ',
              "Idon's Theft"               => 'IT',
              'Ignite'                     => 'Ignite',
              'Imbue'                      => 'Imbue',
              'Innocence'                  => 'Innocence',
              'Instinct'                   => 'INST',
              'Invocation of the Spheres'  => 'IOTS',
              'Iron Constitution'          => 'IC',
              'Iridius Rod'                => 'IR',
              'Ivory Mask'                 => 'IVM',
              'Kura-Silma'                 => 'KS',
              'Last Gift of Vithwok IV'    => 'LGV',
              'Lay Ward'                   => 'LW',
              'Lethargy'                   => 'LETHARGY',
              'Lightning Bolt'             => 'LB',
              'Locate'                     => 'Locate',
              "Machinist's Touch"          => 'MT',
              'Magnetic Ballista'          => 'MAB',
              'Major Physical Protection'  => 'MAPP',
              'Malediction'                => 'Malediction',
              'Manifest Force'             => 'MAF',
              'Mantle of Flame'            => 'MOF',
              'Mark of Arhat'              => 'MOA',
              'Marshal Order'              => 'MO',
              'Mask of the Moons'          => 'MOM',
              'Mass Rejuvenation'          => 'MRE',
              "Membrach's Greed"           => 'MEG',
              'Memory of Nature'           => 'MON',
              'Mental Blast'               => 'MB',
              'Mental Focus'               => 'MEF',
              "Meraud's Cry"               => 'MC',
              'Mind Shout'                 => 'MS',
              'Minor Physical Protection'  => 'MPP',
              'Misdirection'               => 'MIS',
              'Moonblade'                  => 'Moonblade',
              'Moongate'                   => 'MG',
              "Murrula's Flames"           => 'MF',
              'Naming of Tears'            => 'NAME',
              'Necrotic Reconstruction'    => 'NR',
              'Nexus'                      => 'NEXUS',
              "Nissa's Binding"            => 'NB',
              'Nonchalance'                => 'NON',
              'Noumena'                    => 'NOU',
              'Oath of the Firstborn'      => 'OATH',
              'Obfuscation'                => 'Obfuscation',
              'Osrel Meraud'               => 'OM',
              "Paeldryth's Wrath"          => 'PW',
              'Paralysis'                  => 'PARALYSIS',
              'Partial Displacement'       => 'PD',
              "Perseverance of Peri'el"    => 'POP',
              'Persistence of Mana'        => 'POM',
              'Petrifying Visions'         => 'PV',
              "Phelim's Sanction"          => 'PS',
              "Philosopher's Preservation" => 'PHP',
              'Piercing Gaze'              => 'PG',
              "Phoenix's Pyre"             => 'PYRE',
              'Platinum Hands of Kertigen' => 'PHK',
              'Protection from Evil'       => 'PFE',
              'Psychic Shield'             => 'PSY',
              'Quicken the Earth'          => 'QE',
              'Rage of the Clans'          => 'RAGE',
              'Raise Power'                => 'RP',
              'Read the Ripples'           => 'RtR',
              'Rebuke'                     => 'REB',
              "Redeemer's Pride"           => 'REPR',
              'Refractive Field'           => 'RF',
              'Refresh'                    => 'Refresh',
              'Regalia'                    => 'REGAL',
              'Regenerate'                 => 'Regenerate',
              'Rejuvenation'               => 'REJUV',
              'Rend'                       => 'rend',
              "Researcher's Insight"       => 'REI',
              'Resonance'                  => 'Resonance',
              'Resurrection'               => 'REZZ',
              'Revelation'                 => 'Revelation',
              'Reverse Putrefaction'       => 'RPU',
              'Riftal Summons'             => 'RS',
              'Righteous Wrath'            => 'RW',
              'Rimefang'                   => 'RIM',
              'Ring of Spears'             => 'ROS',
              'Rising Mists'               => 'RM',
              'Rite of Contrition'         => 'ROC',
              'Rite of Grace'              => 'ROG',
              'Rite of Forbearance'        => 'ROF',
              'River in the Sky'           => 'RITS',
              "Rutilor's Edge"             => 'RUE',
              'Saesordian Compass'         => 'SCO',
              'Sanctify Pattern'           => 'SAP',
              'Sanctuary'                  => 'Sanctuary',
              'Sanyu Lyba'                 => 'SL',
              'Seal Cambrinth'             => 'SEC',
              "Seer's Sense"               => 'SEER',
              'See the Wind'               => 'STW',
              'Senses of the Tiger'        => 'SOTT',
              "Sentinel's Resolve"         => 'SR',
              'Sever Thread'               => 'SET',
              'Shadewatch Mirror'          => 'SHM',
              'Shadow Servant'             => 'SS',
              'Shadowling'                 => 'Shadowling',
              'Shadows'                    => 'Shadows',
              'Shadow Web'                 => 'SHW',
              'Shatter'                    => 'Shatter',
              'Shear'                      => 'shear',
              'Shield of Light'            => 'SOL',
              'Shift Moonbeam'             => 'SM',
              'Shockwave'                  => 'Shockwave',
              'Siphon Vitality'            => 'SV',
              'Skein of Shadows'           => 'SKS',
              'Sleep'                      => 'Sleep',
              'Smite Horde'                => 'SMH',
              "Soldier's Prayer"           => 'SP',
              'Soul Ablaze'                => 'SOUL',
              'Soul Attrition'             => 'SA',
              'Soul Bonding'               => 'SB',
              'Soul Shield'                => 'SOS',
              'Soul Sickness'              => 'SICK',
              'Sovereign Destiny'          => 'SOD',
              'Spite of Dergati'           => 'SPIT',
              'Stampede'                   => 'Stampede',
              'Starcrash'                  => 'Starcrash',
              'Starlight Sphere'           => 'SLS',
              'Stellar Collector'          => 'STC',
              'Steps of Vuan'              => 'SOV',
              'Stone Strike'               => 'STS',
              'Strange Arrow'              => 'STRA',
              'Stun Foe'                   => 'SF',
              'Substratum'                 => 'Substratum',
              'Sure Footing'               => 'SUF',
              'Swarm'                      => 'Swarm',
              'Swirling Winds'             => 'SW',
              'Syamelyo Kuniyo'            => 'SK',
              'Tailwind'                   => 'TW',
              'Tangled Fate'               => 'TF',
              "Tamsine's Kiss"             => 'TK',
              'Telekinetic Shield'         => 'TKSH',
              'Telekinetic Storm'          => 'TKS',
              'Telekinetic Throw'          => 'TKT',
              'Teleport'                   => 'Teleport',
              'Tenebrous Sense'            => 'TS',
              "Tezirah's Veil"             => 'TV',
              'Thoughtcast'                => 'TH',
              'Thunderclap'                => 'TC',
              'Tingle'                     => 'TI',
              'Trabe Chalice'              => 'TRC',
              'Tranquility'                => 'Tranquility',
              'Tremor'                     => 'Tremor',
              "Truffenyi's Rally"          => 'TR',
              'Turmar Illumination'        => 'TURI',
              'Uncurse'                    => 'Uncurse',
              'Universal Solvent'          => 'USOL',
              'Unleash'                    => 'Unleash',
              'Veil of Ice'                => 'VOI',
              'Vertigo'                    => 'Vertigo',
              'Vessel of Salvation'        => 'VOS',
              'Vigil'                      => 'Vigil',
              'Vigor'                      => 'Vigor',
              'Viscous Solution'           => 'VS',
              'Visions of Darkness'        => 'VOD',
              'Vitality Healing'           => 'VH',
              'Vivisection'                => 'Vivisection',
              'Ward Break'                 => 'WB',
              'Whispers of the Muse'       => 'WOTM',
              'Whole Displacement'         => 'WD',
              'Will of Winter'             => 'WILL',
              'Wisdom of the Pack'         => 'WOTP',
              'Wolf Scent'                 => 'WS',
              'Words of the Wind'          => 'WORD',
              "Worm's Mist"                => 'WORM',
              "Y'ntrel Sechra"             => 'YS',
              'Zephyr'                     => 'zephyr'
            }

            # Reduce lines a bit
            text.sub!(/ (roisaen|roisan)/, '')
            text.sub!(/Indefinite/, 'cyclic')
            text.sub!(/Khri /, '')

            if text.index('(')
              spell_name = text[0..text.index('(') - 2]
              # Shorten spell names
              text.sub!(/^#{spell_name}/, all_spells[spell_name.strip]) if all_spells.include?(spell_name.strip)
            end

            text.strip!

            SETTINGS_LOCK.synchronize do
              HIGHLIGHT.each_pair do |regex, colors|
                pos = 0
                while (match_data = text.match(regex, pos))
                  h = {
                    start: match_data.begin(0),
                    end: match_data.end(0),
                    fg: colors[0],
                    bg: colors[1],
                    ul: colors[2]
                  }
                  line_colors.push(h)
                  pos = match_data.end(0)
                end
              end
            end

            line_colors.push(start: 0, fg: PRESET[current_stream][0], bg: PRESET[current_stream][1],
                             end: text.length)
            # window.add_string(text, line_colors)
            # need_update = true
          end
          unless text =~ /^\[server\]: "(?:kill|connect)/
            window.add_string(text, line_colors)
            need_update = true
          end
        elsif current_stream =~ /^(?:death|logons|thoughts|voln|familiar|assess|ooc|shopWindow|combat|moonWindow|atmospherics)$/
          if (window = stream_handler['main'])
            if PRESET[current_stream]
              line_colors.push(start: 0, fg: PRESET[current_stream][0], bg: PRESET[current_stream][1],
                               end: text.length)
            end
            unless text.empty?
              if need_prompt
                need_prompt = false
                add_prompt(window, prompt_text)
              end
              window.add_string(text, line_colors)
              need_update = true
            end
          end
        end
      elsif (window = stream_handler['main'])
        if need_prompt
          need_prompt = false
          add_prompt(window, prompt_text)
        end
        window.add_string(text, line_colors)
        need_update = true
      end
    end
    line_colors = []
    open_monsterbold.clear
    open_preset.clear
    open_color.clear
  }

  while (line = server.gets)

    if line =~ /^<popBold\/>/
      bold_next_line = false
    elsif bold_next_line == true
      line = "<pushBold/>#{line.chomp}<popBold/>\n"
    elsif line =~ /<pushBold\/>\r\n$/
      bold_next_line = true
    end

    line.chomp!

    if line.match(gag_regexp)
      # p line.inspect
      File.write("gaglog.txt", line.inspect + "\n", mode: "a")
      # line = nil
      next
    elsif line.match(/#{LOCALUSERNAME.strip}/)
      line.sub!(LOCALUSERNAME.strip, 'mahtra')
    elsif line.empty? # || line.nil?
      emptycount += 1
      if emptycount > 1
        line = nil
        next
      end
    else
      emptycount = 0
    end

    # if line.match(/The moth/)
    #   File.write("mothlog.txt", line.inspect + "\n", mode: "a")
    # end

    if line.empty?
      if current_stream.nil?
        if need_prompt
          need_prompt = false
          add_prompt(stream_handler['main'], prompt_text)
        end
        stream_handler['main'].add_string String.new
        need_update = true
      end
    else
      while (start_pos = (line =~ /(<(prompt|spell|right|left|inv|compass).*?\2>|<.*?>)/))
        xml = Regexp.last_match(1)
        line.slice!(start_pos, xml.length)
        if xml =~ %r{^<prompt time=('|")([0-9]+)\1.*?>(.*?)&gt;</prompt>$}
          unless skip_server_time_offset
            $server_time_offset = Time.now.to_f - Regexp.last_match(2).to_f
            skip_server_time_offset = true
          end
          new_prompt_text = "#{Regexp.last_match(3)}>"
          if prompt_text != new_prompt_text
            need_prompt = false
            prompt_text = new_prompt_text
            add_prompt(stream_handler['main'], new_prompt_text)
            if (prompt_window = indicator_handler['prompt'])
              init_prompt_height = fix_layout_number.call(prompt_window.layout[0])
              init_prompt_width = fix_layout_number.call(prompt_window.layout[1])
              new_prompt_width = new_prompt_text.length
              prompt_window.resize(init_prompt_height, new_prompt_width)
              prompt_width_diff = new_prompt_width - init_prompt_width
              command_window.resize(fix_layout_number.call(command_window_layout[0]),
                                    fix_layout_number.call(command_window_layout[1]) - prompt_width_diff)
              ctop = fix_layout_number.call(command_window_layout[2])
              cleft = fix_layout_number.call(command_window_layout[3]) + prompt_width_diff
              command_window.move(ctop, cleft)
              prompt_window.label = new_prompt_text
            end
          else
            need_prompt = true
          end
        elsif xml =~ %r{^<spell(?:>|\s.*?>)(.*?)</spell>$}
          if (window = indicator_handler['spell'])
            window.clear
            window.label = Regexp.last_match(1)
            window.update(Regexp.last_match(1) == 'None' ? 0 : 1)
            need_update = true
          end
        elsif xml =~ %r{^<(right|left)(?:>|\s.*?>)(.*?\S*?)</\1>}
          if (window = indicator_handler[Regexp.last_match(1)])
            window.clear
            window.label = Regexp.last_match(2)
            window.update(Regexp.last_match(2) == 'Empty' ? 0 : 1)
            need_update = true
          end
        elsif xml =~ /^<roundTime value=('|")([0-9]+)\1/
          if (window = countdown_handler['roundtime'])
            temp_roundtime_end = Regexp.last_match(2).to_i
            window.end_time = temp_roundtime_end
            window.update
            need_update = true
            Thread.new do
              sleep 0.15
              while (countdown_handler['roundtime'].end_time == temp_roundtime_end) and (countdown_handler['roundtime'].value > 0)
                sleep 0.15
                if countdown_handler['roundtime'].update
                  command_window.noutrefresh
                  Curses.doupdate
                end
              end
            end
          end
        elsif xml =~ /^<castTime value=('|")([0-9]+)\1/
          if (window = countdown_handler['roundtime'])
            temp_casttime_end = Regexp.last_match(2).to_i
            window.secondary_end_time = temp_casttime_end
            window.update
            need_update = true
            Thread.new do
              while (countdown_handler['roundtime'].secondary_end_time == temp_casttime_end) and (countdown_handler['roundtime'].secondary_value > 0)
                sleep 0.15
                if countdown_handler['roundtime'].update
                  command_window.noutrefresh
                  Curses.doupdate
                end
              end
            end
          end
        elsif xml =~ /^<compass/
          current_dirs = xml.scan(/<dir value="(.*?)"/).flatten
          for dir in %w[up down out n ne e se s sw w nw]
            next unless (window = indicator_handler["compass:#{dir}"])

            need_update = true if window.update(current_dirs.include?(dir))
          end
        elsif xml =~ /^<progressBar id='(.*?)' value='[0-9]+' text='.* ([0-9]+)%/
          if (window = progress_handler[Regexp.last_match(1)]) && window.update(Regexp.last_match(2).to_i, 100)
            need_update = true
          end
        elsif xml =~ /^<progressBar id='pbarStance' value='([0-9]+)'/
          if (window = progress_handler['stance']) && window.update(Regexp.last_match(1).to_i, 100)
            need_update = true
          end
        elsif xml =~ /^<progressBar id='mindState' value='(.*?)' text='(.*?)'/
          if (window = progress_handler['mind'])
            value = if Regexp.last_match(2) == 'saturated'
                      110
                    else
                      Regexp.last_match(1).to_i
                    end
            need_update = true if window.update(value, 110)
          end

        elsif ['<pushBold/>', '<b>'].include?(xml)
          h = { start: start_pos }
          if PRESET['monsterbold']
            h[:fg] = PRESET['monsterbold'][0]
            h[:bg] = PRESET['monsterbold'][1]
          end
          open_monsterbold.push(h)
        elsif ['<popBold/>', '</b>'].include?(xml)
          if (h = open_monsterbold.pop)
            h[:end] = start_pos
            line_colors.push(h) if h[:fg] or h[:bg]
          end
        elsif xml =~ /^<preset id=('|")(.*?)\1>$/
          h = { start: start_pos }
          if PRESET[Regexp.last_match(2)]
            h[:fg] = PRESET[Regexp.last_match(2)][0]
            h[:bg] = PRESET[Regexp.last_match(2)][1]
          end
          open_preset.push(h)
        elsif xml == '</preset>'
          if (h = open_preset.pop)
            h[:end] = start_pos
            line_colors.push(h) if h[:fg] or h[:bg]
          end
        elsif xml =~ /^<color/
          h = { start: start_pos }
          h[:fg] = Regexp.last_match(2).downcase if xml =~ /\sfg=('|")(.*?)\1[\s>]/
          h[:bg] = Regexp.last_match(2).downcase if xml =~ /\sbg=('|")(.*?)\1[\s>]/
          h[:ul] = Regexp.last_match(2).downcase if xml =~ /\sul=('|")(.*?)\1[\s>]/
          open_color.push(h)
        elsif xml == '</color>'
          if (h = open_color.pop)
            h[:end] = start_pos
            line_colors.push(h)
          end
        elsif xml =~ /^<style id=('|")(.*?)\1/
          if Regexp.last_match(2).empty?
            if open_style
              open_style[:end] = start_pos
              if (open_style[:start] < open_style[:end]) and (open_style[:fg] or open_style[:bg])
                line_colors.push(open_style)
              end
              open_style = nil
            end
          else
            open_style = { start: start_pos }
            if PRESET[Regexp.last_match(2)]
              open_style[:fg] = PRESET[Regexp.last_match(2)][0]
              open_style[:bg] = PRESET[Regexp.last_match(2)][1]
            end
          end
        elsif xml =~ %r{<(?:pushStream|component) id=("|')(.*?)\1[^>]*/?>}
          new_stream = Regexp.last_match(2)
          if new_stream =~ /^exp (\w+\s?\w+?)/
            current_stream = 'exp'
            stream_handler['exp'].set_current(Regexp.last_match(1)) if stream_handler['exp']
          # elsif new_stream =~ /^moonWindow/
          # 	current_stream = 'moonWindow'
          # 	stream_handler['moonWindow'].clear_spells if stream_handler['moonWindow']
          else
            current_stream = new_stream
          end
          game_text = line.slice!(0, start_pos)
          handle_game_text.call(game_text)
        elsif xml =~ %r{^<popStream(?!/><pushStream)} or xml == '</component>'
          game_text = line.slice!(0, start_pos)
          handle_game_text.call(game_text)
          stream_handler['exp'].delete_skill if current_stream == 'exp' and stream_handler['exp']
          current_stream = nil
        elsif xml =~ %r{^<clearStream id="percWindow"/>$}
          stream_handler['percWindow'].clear_spells if stream_handler['percWindow']
        elsif xml =~ /^<progressBar/
          nil
        elsif xml =~ %r{^<(?:dialogdata|a|/a|d|/d|/?component|label|skin|output)}
          nil
        elsif xml =~ /^<indicator id=('|")Icon([A-Z]+)\1 visible=('|")([yn])\3/
          if (window = countdown_handler[Regexp.last_match(2).downcase])
            window.active = (Regexp.last_match(4) == 'y')
            need_update = true if window.update
          end
          if (window = indicator_handler[Regexp.last_match(2).downcase]) && window.update(Regexp.last_match(4) == 'y')
            need_update = true
          end
        elsif xml =~ /^<image id=('|")(back|leftHand|rightHand|head|rightArm|abdomen|leftEye|leftArm|chest|rightLeg|neck|leftLeg|nsys|rightEye)\1 name=('|")(.*?)\3/
          if Regexp.last_match(2) == 'nsys'
            if (window = indicator_handler['nsys'])
              if (rank = Regexp.last_match(4).slice(/[0-9]/))
                need_update = true if window.update(rank.to_i)
              elsif window.update(0)
                need_update = true
              end
            end
          else
            fix_value = { 'Injury1' => 1, 'Injury2' => 2, 'Injury3' => 3, 'Scar1' => 4, 'Scar2' => 5, 'Scar3' => 6 }
            if (window = indicator_handler[Regexp.last_match(2)]) && window.update(fix_value[Regexp.last_match(4)] || 0)
              need_update = true
            end
          end
        elsif xml =~ /^<LaunchURL src="([^"]+)"/
          url = "https://www.play.net#{Regexp.last_match(1)}"
          # assume linux if not mac
          # TODO somehow determine whether we are running in a gui environment?
          # for now, just print it instead of trying to open it
          # cmd = RUBY_PLATFORM =~ /darwin/ ? "open" : "firefox"
          # system("#{cmd} #{url}")
          stream_handler['main'].add_string ' *'
          stream_handler['main'].add_string " * LaunchURL: #{url}"
          stream_handler['main'].add_string ' *'
        end
      end
      handle_game_text.call(line)
    end
    #
    # delay screen update if there are more game lines waiting
    #
    next unless need_update and !IO.select([server], nil, nil, 0.01)

    need_update = false
    command_window.noutrefresh
    Curses.doupdate
  end
  stream_handler['main'].add_string ' *'
  stream_handler['main'].add_string ' * Connection closed'
  stream_handler['main'].add_string ' *'
  command_window.noutrefresh
  Curses.doupdate
  exit
rescue StandardError
  File.open('profanity.log', 'a') do |f|
    f.puts $!
    f.puts $!.backtrace[0...4]
  end
  exit
end

begin
  key_combo = nil
  loop do
    ch = command_window.getch
    if key_combo
      if key_combo[ch].instance_of?(Proc)
        key_combo[ch].call
        key_combo = nil
      elsif key_combo[ch].instance_of?(Hash)
        key_combo = key_combo[ch]
      else
        key_combo = nil
      end
    elsif key_binding[ch].instance_of?(Proc)
      key_binding[ch].call
    elsif key_binding[ch].instance_of?(Hash)
      key_combo = key_binding[ch]
    elsif ch.instance_of?(String)
      command_window_put_ch.call(ch)
      command_window.noutrefresh
      Curses.doupdate
    end
  end
rescue StandardError
  File.open('profanity.log', 'a') do |f|
    f.puts $!
    f.puts $!.backtrace[0...4]
  end
ensure
  begin
    server.close
  rescue StandardError
    # ()
  end
  Curses.close_screen
end
