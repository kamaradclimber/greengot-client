#!/usr/bin/env ruby

require 'qif'
require 'json'

def extract(parse, field)
  parse[field].gsub(/^"/, '').gsub(/"$/, '')
end

# read all input
transactions = []
loop do
  line = STDIN.gets
  break if line.nil?
  next if line =~ /^"Transaction ID",/

  parsed = line.split(",")
  transaction = {}
  transaction["id"] = extract(parsed, 0)
  transaction["amount"] = { "currency" => extract(parsed, 5), "value" => extract(parsed, 3).to_f }
  transaction["status"] = extract(parsed, 1)
  transaction["createdAt"] = extract(parsed, 2)
  transaction["direction"] = extract(parsed, 4)
  transaction["iban"] = extract(parsed, 6)
  transaction["counterparty"] = extract(parsed, 7)
  transaction["counterparty_iban"] = extract(parsed, 8)
  transaction["payment_method"] = extract(parsed, 9)
  transaction["reference"] = extract(parsed, 11)


  transactions << transaction
end

output_file = 'output.qif'

warn "Writing output to #{output_file}"

Qif::Writer.open(output_file, 'Bank', 'dd/mm/yyyy') do |qif|
  transactions.each_with_index do |transaction, index|
    STDERR.puts "Processing #{index+1}/#{transactions.size}"

    raise "Payment #{transaction['id']} is not in euros but in #{transaction['amount']['currency']}" unless transaction['amount']['currency'] == 'EUR'

    case transaction['status']
    when 'AUTHORISED', 'COMPLETE'
      nil
    when 'CANCELLED', 'EXPIRED'
      next
    else
      raise "Unknown status #{transaction['status']} for #{transaction['id']}"
    end


    date  = Time.parse(transaction['createdAt']).to_date
    amount = case transaction['direction']
              when 'DEBIT'
                - transaction['amount']['value'].to_f
              when 'CREDIT'
                transaction['amount']['value'].to_f
              else
                raise "Unknown direction #{transaction['direction']} for payment #{transaction['id']}"
              end

    memo = [
      transaction['reference'],
      transaction['note']
    ].compact.join(" - ")

    qif << Qif::Transaction.new(
      date: date,
      amount: amount,
      status: nil,
      number: nil,
      payee: transaction['counterparty'],
      memo: memo,
      adress: nil,
      category: '',
    )
  end
end
