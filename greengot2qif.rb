#!/usr/bin/env ruby

require 'qif'
require 'json'

# read all input
all_lines = []
loop do
  line = STDIN.gets
  break if line.nil?

  all_lines << line
end
transactions = JSON.parse(all_lines.join)

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
                - transaction['amount']['value'].to_f / 100
              when 'CREDIT'
                transaction['amount']['value'].to_f / 100
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
