def putsnb(s)
  puts Time.now.strftime("%H:%M:%S") + ': ' + s
  $stdout.flush
end

def geo2dec(pos)
  # pozycję mamy w formacie: 18E47'13"
  deg = m = s = ''
  found_dir = found_min = found_sec = nil

  pos.chars.each do |char|
    if ['E', 'W', 'S', 'N'].include?(char) && found_dir.nil?
      found_dir = char
      next
    end
    if "'" == char
      found_min = true
      next
    end
    if '"' == char
      found_sec = true
      next
    end

    deg = deg + char if found_dir.nil?
    m = m + char if found_dir && found_min.nil?
    s = s + char if found_dir && found_min && found_sec.nil?
  end

  deg.to_f + (m.to_f * 1/60) + (s.to_f * 1/60 * 1/60)
end

def row2hash(row)
  #0 : A :Nr referencyjny
  #1 : B: Ważna do
  #2 : C: Nazwa stacji
  #3 : D: Rodz stacji
  #4 : E: Rodz sieci
  #5 : F: Dł geo
  #6 : G: Szer geo
  #7 : H: R obsł
  #8 : I: Lokalizacja stacji
  #9 : J: ERP
  #10: K: Azymut
  #11: L: Elewacja
  #12: M: Polar
  #13: N: Zysk ant
  #14: O: H anteny
  #15: P: H terenu
  #16: Q: Ch-ka poz
  #17: R: Ch-ka pion
  #18: S: Częstotliwości nadawcze
  #19: T: Częstotliwości odbiorcze
  #20: U: Szer kanałów nad
  #21: V: Szer kanałów odb
  #22: W: Operator
  #23: X: Adres operatora
  h = {
    permit: {
      number:     row[0],
      valid_to:   row[1]
    },

    station: {
      name:             row[2],
      purpose:          row[3],
      net:              row[4],
      lon:              geo2dec(row[5]).round(6),
      lat:              geo2dec(row[6]).round(6),
      radius:           row[7] ? row[7].to_i : nil,
      location:         row[8],
      erp:              row[9].to_f.round(1),
      ant_efficiency:   row[13].to_f.round(1),
      ant_height:       row[14].to_i,
      ant_polarisation: row[12],
      directional:      (row[10].strip == '' ? false : true),
      name_unified:     Uke::Unifier::indexify_string(row[2] + row[8])
    },

    frq_tx:     row[18].gsub(/\s+/, '').split(',').map{|frq| frq.to_f}.keep_if{|frq| frq > 0},
    frq_rx:     row[19].gsub(/\s+/, '').split(',').map{|frq| frq.to_f}.keep_if{|frq| frq > 0},

    operator: {
      name:     row[22],
      address:  row[23],
      name_unified: Uke::Unifier::indexify_string(row[22])
    }
  }
end

def insert_row(row, uke_import)
  permit = UkePermit.find_by_number row[:permit][:number]
  permit = UkePermit.create! row[:permit] if permit.nil?

  operator = UkeOperator.find_by_name_unified row[:operator][:name_unified]
  operator = UkeOperator.create! row[:operator] if operator.nil?

  any_news = false
  station = UkeStation.where(name_unified: row[:station][:name_unified], uke_operator: operator).first

  if station.nil?
    any_news = true
    station = UkeStation.new row[:station]
    station.uke_operator = operator
  end

  station.uke_import = uke_import
  station.uke_permit = permit
  station.save!
  
  row[:frq_rx].each do |mhz|
    frequency = Frequency.find_or_create_by!(mhz: mhz)
    frequency_assignment = station.frequency_assignments.where(usage: 'RX', frequency: frequency).first
    if frequency_assignment.nil?
      station.frequency_assignments << FrequencyAssignment.new(frequency: frequency, usage: 'RX', uke_import: uke_import)
      any_news = true
    else
      frequency_assignment.uke_import = uke_import
      frequency_assignment.save!
    end
  end
  
  row[:frq_tx].each do |mhz|
    frequency = Frequency.find_or_create_by!(mhz: mhz)
    frequency_assignment = station.frequency_assignments.where(usage: 'TX', frequency: frequency).first
    if frequency_assignment.nil?
      station.frequency_assignments << FrequencyAssignment.new(frequency: frequency, usage: 'TX', uke_import: uke_import)
      any_news = true
    else
      frequency_assignment.uke_import = uke_import
      frequency_assignment.save!  
    end
  end

  if any_news && UkeImportNews.where(uke_import: uke_import, uke_station: station).first.nil?
    UkeImportNews.create(uke_import: uke_import, uke_station: station)
    putsnb "News on station #{station.id}/#{station.display_name}"
  end
end

ARGV.each do|a|
  putsnb "Argument: #{a}"
  @import_release_date = a.sub(/--release-date=/, '').to_s unless (a =~ /--release-date=/).nil?
end

if @import_release_date.nil?
  putsnb "Give UKE database release date as --release-date= argument"
  exit
end

@uke_import = UkeImport.find_by_released_on(Date.parse(@import_release_date))
if @uke_import.nil?
  putsnb "Release not found, please create one using ss_import_create.rb"
  exit
end

putsnb "UKE import release #{@uke_import.id}/#{@uke_import.released_on.to_s}"

Dir["#{Rails.root.to_s}/tmp/ss/#{@import_release_date}/*"].each do |xls_file|
  putsnb "File #{xls_file}\n"

  book = Roo::Spreadsheet.open(xls_file)
  book.default_sheet = book.sheets.first

  num_of_rows = book.last_row
  num_of_rows_processed = 0
  last_percent_out = nil

  putsnb "#{num_of_rows.to_s} rows to process, starting..."

  0.upto(book.last_row) do |index|
    if index > 1
      row = book.row(index)
      begin
        insert_row(row2hash(row), @uke_import)
      rescue => e
        puts e.to_s
        puts row2hash(row).inspect
      end

      num_of_rows_processed += 1
      percent_processed = ((num_of_rows_processed.to_f/num_of_rows.to_f)*100).round(0).to_i

      if 0 == (percent_processed%10) && percent_processed != last_percent_out
        putsnb "Processed #{percent_processed}% of #{xls_file}"
        last_percent_out = percent_processed
      end
    end
  end
end

UkeImport.all.each do |uke_import|
  uke_import.active = false
  uke_import.save!
end

uia = UkeImport.find(@uke_import.id)
uia.active = true
uia.save!

putsnb "Done"
