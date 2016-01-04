#encoding: UTF-8
require 'scraperwiki'
ScraperWiki.sqliteexecute('DROP TABLE IF EXISTS swvariables');
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

require 'open-uri'
require 'yaml'
require "hpricot"
class Array
  def to_yaml_style
    :inline
  end
end
baseurl = "http://www.lobbyistsregister.vic.gov.au/lobbyistsregister"
html = ScraperWiki.scrape("http://www.lobbyistsregister.vic.gov.au/lobbyistsregister/index.cfm?event=whoIsOnRegister")

# Next we use Nokogiri to extract the values from the HTML source.

require 'nokogiri'
cleanhtml = html.force_encoding("binary").gsub(/[^[:print:]]/, "")
utfhtml = cleanhtml.encode('UTF-8')
fixed_html = Nokogiri::HTML::DocumentFragment.parse(utfhtml).to_html
page = Nokogiri::HTML(fixed_html)
urls = page.at('table').search('a').map { |a| a.attributes['href'] }

urls.map do |url|
  url = "#{baseurl}/#{url}"

  puts "Downloading #{url}"
  begin
    lobbyhtml = Hpricot(ScraperWiki.scrape(url).strip).at("#contentLeft").inner_html # clean up broken html using Hpricot first
    lobbypage = Nokogiri::HTML::Document.parse(lobbyhtml)

    #thanks http://ponderer.org/download/xpath/ and http://www.zvon.org/xxl/XPathTutorial/Output/
    employees = []
    clients = []
    owners = []
    names = []
    lobbyist_firm = {}

    companyABN=lobbypage.xpath("//tr/td/b[text() = 'A.B.N: ']/ancestor::td/following-sibling::node()/text()")
    companyName=lobbypage.xpath("//b[text() = 'Company Details']/ancestor::table/following-sibling::node()//b[text() = 'Name: ']/ancestor::td/following-sibling::node()[2]/text()").first
    lobbyist_firm["business_name"] = companyName.to_s
    lobbyist_firm["trading_name"] = companyName.to_s
    lobbyist_firm["abn"] =  companyABN.to_s
    lobbypage.xpath("//b[text() = 'Client Details']/ancestor::table/following-sibling::table[1]//tr/td[2]/text()").each do |client|
      clientName = client.content.gsub(/\u00a0/, '').strip
      if clientName.empty? == false and clientName.class != 'binary'
        clients << { "lobbyist_firm_name" => lobbyist_firm["business_name"],"lobbyist_firm_abn" => lobbyist_firm["abn"], "name" => clientName }
      end
    end
    lobbypage.xpath("//b[text() = 'Owner Details']/ancestor::table/following-sibling::table[1]//tr/td[2]/text()").each do |owner|
      ownerName = owner.content.gsub(/\u00a0/, '').strip
      if ownerName.empty? == false and ownerName.class != 'binary'
        owners << { "lobbyist_firm_name" => lobbyist_firm["business_name"],"lobbyist_firm_abn" => lobbyist_firm["abn"], "name" => ownerName }

      end
    end
    lastEmployee = {}
    lobbypage.xpath("//b[text() = 'Lobbyist Details']/ancestor::table/following-sibling::table[1]//tr/td[2]/text()[1]").each do |employee|
      employeeField = employee.content.gsub(/\u00a0/, '').gsub("  ", " ").strip
      if employeeField.empty? == false and employeeField.class != 'binary'
        if (lastEmployee.empty? == true)
          lastEmployee["name"] = employeeField

          employees << { "lobbyist_firm_name" => lobbyist_firm["business_name"],"lobbyist_firm_abn" => lobbyist_firm["abn"], "name" =>  lastEmployee["name"]}
        end
      end
    end
    lobbypage.xpath("//b[text() = 'Details Last Updated: ']/ancestor::td/text()").each do |lastup|
      lastUpClean = lastup.content.gsub(/\u00a0/, '').gsub("  ", " ").gsub('Details Last Updated:', '').strip
      if lastUpClean.empty? == false and lastUpClean.class != 'binary'
        lobbyist_firm["last_updated"] = lastUpClean
      end
    end


    ScraperWiki.save(unique_keys=["name","lobbyist_firm_abn"],data=employees, table_name="lobbyists")
    ScraperWiki.save(unique_keys=["name","lobbyist_firm_abn"],data=clients, table_name="lobbyist_clients")
    ScraperWiki.save(unique_keys=["name","lobbyist_firm_abn"],data=owners, table_name="lobbyist_firm_owners")
    ScraperWiki.save(unique_keys=["business_name","abn"],data=lobbyist_firm, table_name="lobbyist_firms")
  rescue Timeout::Error => e
    print "Timeout on #{url}"
  end
end
