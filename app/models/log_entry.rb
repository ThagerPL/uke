class LogEntry < ActiveRecord::Base
  belongs_to :user
  belongs_to :log
  belongs_to :related_frequency_assignment, class_name: 'FrequencyAssignment'

  has_one :frequency_assignment, as: :subject

  has_one :frequency, through: :frequency_assignment

  attr_accessor :mhz
  attr_accessor :selected_panel

  delegate :mhz, to: :frequency, prefix: true

  delegate :display_name, to: :related_frequency_assignment, allow_nil: true, prefix: :related_frequency
  delegate :display_name, to: :bandplan, allow_nil: true, prefix: true

  scope :my, lambda{|user| where(user_id: user.id)}

  validate :mhz do
    mhz = Uke::Unifier::frq_string(@mhz)

    errors.add(:mhz, :out_of_range) if mhz < 25 || mhz > 520
    bandplan = Bandplan.find_by_mhz mhz
    errors.add(:mhz, :step_invalid) if bandplan && bandplan.step && (mhz*1000)%bandplan.step != 0

    self.log.log_entries.each do |log_entry|
      errors.add(:mhz, :duplicate) if log_entry.frequency.mhz == mhz
    end
  end

  validates :description, allow_blank: true, length: {maximum: 255}
  validates :level, inclusion: { in: 1..5 }
  validates :net, inclusion: {in: Uke::Net::all}

  validates :administrative_area_level_2, presence: true, :length => {:maximum => 255}, if: :has_location?
  validates :administrative_area_level_1, presence: true, :length => {:maximum => 255}, if: :has_location?
  validates :country, presence: true, length: {:maximum => 255}, if: :has_location?
  validates :lon, presence: true, inclusion: { in: -180..180 }, if: :has_location?
  validates :lat, presence: true, inclusion: { in: -90..90 }, if: :has_location?

  after_validation do
    frequency = Frequency.find_or_create_by!(mhz: mhz)
    self.frequency_assignment = FrequencyAssignment.new(frequency: frequency, usage: 'RX')
  end

  def has_location?
    %w(collapse-uke-list collapse-map).include?(@selected_panel)
  end

  def bandplan
    Bandplan.find_by_mhz(frequency.mhz)
  end

  def source
    user.nickname
  end

  def display_name
    description
  end
end
