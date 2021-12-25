require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'http-cookie'
  gem 'httpclient'
  gem 'nokogiri'
end

require 'json'
require 'logger'

YEAR = (ARGV.shift || "2021")

class Scraper
  def scrape
    logger = Logger.new($stderr)

    doc('https://boomkat.com/charts/boomkat-end-of-year-charts-%s' % YEAR).
      css('.charts-index-chart').
      find_all do |a|
      a['href'] && a['href'] !~ /\/charts\/boomkat-end-of-year-charts-#{YEAR}\/94[012]/
    end.inject({}) do |memo, a|
      data = chart(a['href'])
      logger.info("scraped a chart by %s" % data[:chart_by])
      data[:items].each_with_index do |item, index|
        memo[item[:artist]] ||= {}
        memo[item[:artist]][item[:title]] ||= {
          url: item[:url],
          img_url: item[:img_url],
          label: item[:label],
          genre: item[:genre],
          chart_by: {}
        }
        memo[item[:artist]][item[:title]][:chart_by][data[:chart_by]] = index + 1
      end

      memo
    end.inject([]) do |memo, (artist, titles)|
      memo + titles.map do |title, value|
        {
          artist: artist,
          title: title,
          url: value[:url],
          img_url: value[:img_url],
          label: value[:label],
          genre: value[:genre],
          chart_by: value[:chart_by],
          score: value[:chart_by].inject(0) do |total, (_, rank)|
            total + 1 + (1.0 / (rank * 5))
          end
        }
      end
    end.sort_by do |item|
      item[:score]
    end.reverse
  end

  def chart(url)
    doc = doc('https://boomkat.com' + url)
    chart_author = doc.css('.chart-topbanner-title').text.strip.sub(/ #{YEAR}$/, '')
    doc.css('.chart-item').inject({ chart_by: chart_author }) do |memo, div|
      url = nil
      img_url = nil

      if div.css('a').size > 0
        url = 'https://boomkat.com' + div.css('a')[0]['href']
      end

      if div.css('img').size > 0
        img_url = div.css('img')[0]['src']
      end

      artist = div.css('.release__artist').text.strip
      title = div.css('.release__title').text.strip
      label = div.css('.release__label').text.strip
      genre = div.css('.release__genre').text.strip

      memo[:items] ||= []
      memo[:items] << {
        url: url,
        img_url: img_url,
        artist: artist,
        title: title,
        label: label,
        genre: genre
      }

      memo
    end
  end

  private

  def doc(url)
    body = http.get_content(url)
    sleep 0.2
    Nokogiri::HTML(body)
  end

  def http
    @http ||= HTTPClient.new
  end
end

def main
  puts JSON.generate(
         title: 'Boomkat Charts %s: Merged' % YEAR,
         data: Scraper.new.scrape
       )
end

main
