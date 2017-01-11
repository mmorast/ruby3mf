class Document

  attr_accessor :types
  attr_accessor :relationships
  attr_accessor :models
  attr_accessor :thumbnails
  attr_accessor :textures
  attr_accessor :objects
  attr_accessor :parts
  attr_accessor :zip_filename

  # Relationship schemas
  MODEL_TYPE = 'http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel'
  THUMBNAIL_TYPE = 'http://schemas.openxmlformats.org/package/2006/relationships/metadata/thumbnail'
  TEXTURE_TYPE = 'http://schemas.microsoft.com/3dmanufacturing/2013/01/3dtexture'
  PRINT_TICKET_TYPE = 'http://schemas.microsoft.com/3dmanufacturing/2013/01/printticket'

  # Relationship Type => Class validating relationship type
  RELATIONSHIP_TYPES = {
    MODEL_TYPE => {klass: 'Model3mf', collection: :models},
    THUMBNAIL_TYPE => {klass: 'Thumbnail3mf', collection: :thumbnails},
    TEXTURE_TYPE => {klass: 'Texture3mf', collection: :textures},
    PRINT_TICKET_TYPE => {}
  }

  TEXTURE_TYPES = %w[image/jpeg image/png application/vnd.ms-package.3dmanufacturing-3dmodeltexture]

  def initialize(zip_filename)
    self.models=[]
    self.thumbnails=[]
    self.textures=[]
    self.objects={}
    self.relationships=[]
    self.types=[]
    self.parts=[]
    @zip_filename = zip_filename
  end

  #verify that each texture part in the 3MF is related to the model through a texture relationship in a rels file
  def self.validate_texture_parts(document, log)

    return unless document.types.size > 0
    document.parts.each do |filename|
      ext = File::extname(filename).delete '.'
      content_type = document.types[ext]
      next unless TEXTURE_TYPES.include?(content_type)

      has_relationship = false
      document.textures.each do |texture_file|
        if texture_file[:target] == filename
          has_relationship = true
          break
        end
      end

      next unless !has_relationship
      document.thumbnails.each do |thumbnail_file|
        if thumbnail_file[:target] == filename
          has_relationship = true
          break
        end
      end
      log.context "part names /#{filename}" do |l|
        l.error :texture_without_relationship unless has_relationship
      end
    end
  end

  def self.read(input_file)

    m = new(input_file)
    begin
      Log3mf.context 'zip' do |l|
        begin
          Zip.warn_invalid_date = false

          # check for the general purpose flag set - if so, warn that 3mf may not work on some systems
          if File.read(input_file)[6] == "\b"
            l.warning 'File format: this file may not open on all systems'
          end

          Zip::File.open(input_file) do |zip_file|

            l.info 'Zip file is valid'

            # check for valid, absolute URI's for each path name

            zip_file.each do |part|
              l.context "part names /#{part.name}" do |l|
                unless part.name.end_with? '[Content_Types].xml'
                  begin
                    u = URI part.name
                  rescue ArgumentError
                    l.error :err_uri_bad
                    next
                  end

                  u.path.split('/').each do |segment|
                    l.error :err_uri_hidden_file if (segment.start_with? '.') && !(segment.end_with? '.rels')
                  end
                  m.parts << '/' + part.name unless part.directory?
                end
              end
            end

            l.context 'content types' do |l|
              # 1. Get Content Types
              content_type_match = zip_file.glob('\[Content_Types\].xml').first
              if content_type_match
                m.types = ContentTypes.parse(content_type_match)
              else
                l.error 'Missing required file: [Content_Types].xml', page: 4
              end
            end

            l.context 'relationships' do |l|
              # 2. Get Relationships
              # rel_folders = zip_file.glob('**/_rels')
              # l.fatal_error "Missing any _rels folder", page: 4 unless rel_folders.size>0

              # 2.1 Validate that the top level _rels/.rel file exists
              rel_file = zip_file.glob('_rels/.rels').first
              l.fatal_error 'Missing required file _rels/.rels', page: 4 unless rel_file

              zip_file.glob('**/*.rels').each do |rel|
                m.relationships += Relationships.parse(rel)
              end
            end

            l.context "print tickets" do |l|
              print_ticket_types = m.relationships.select { |rel| rel[:type] == PRINT_TICKET_TYPE }
              l.error :multiple_print_tickets if print_ticket_types.size > 1
            end

            l.context "relationship elements" do |l|
              # 3. Validate all relationships
              m.relationships.each do |rel|
                l.context rel[:target] do |l|

                  begin
                    u = URI rel[:target]
                  rescue URI::InvalidURIError
                    l.error :err_uri_bad
                    next
                  end

                  l.error :err_uri_relative_path unless u.to_s.start_with? '/'

                  target = rel[:target].gsub(/^\//, "")
                  l.error :err_uri_empty_segment if target.end_with? '/' or target.include? '//'
                  l.error :err_uri_relative_path if target.include? '/../'
                  relationship_file = zip_file.glob(target).first

                  if relationship_file
                    relationship_type = RELATIONSHIP_TYPES[rel[:type]]
                    if relationship_type.nil?
                      l.error :invalid_relationship_type, type: rel[:type]
                    else
                      unless relationship_type[:klass].nil?
                        m.send(relationship_type[:collection]) << {
                            rel_id: rel[:id],
                            target: rel[:target],
                            object: Object.const_get(relationship_type[:klass]).parse(m, relationship_file)
                        }
                      end
                    end
                  else
                    l.error "Relationship Target file #{rel[:target]} not found", page: 11
                  end
                end
              end
            end

            validate_texture_parts(m, l)
          end

          return m
        rescue Zip::Error
          l.fatal_error 'File provided is not a valid ZIP archive', page: 9
        end
      end
    rescue Log3mf::FatalError
      #puts "HALTING PROCESSING DUE TO FATAL ERROR"
      return nil
    end
  end

  def write(output_file = nil)
    output_file = zip_filename if output_file.nil?

    Zip::File.open(zip_filename) do |input_zip_file|

      buffer = Zip::OutputStream.write_buffer do |out|
        input_zip_file.entries.each do |e|
          if e.directory?
            out.copy_raw_entry(e)
          else
            out.put_next_entry(e.name)
            if objects[e.name]
              out.write objects[e.name]
            else
              out.write e.get_input_stream.read
            end
          end
        end
      end

      File.open(output_file, 'wb') { |f| f.write(buffer.string) }

    end

  end

  def contents_for(path)
    Zip::File.open(zip_filename) do |zip_file|
      zip_file.glob(path).first.get_input_stream.read
    end
  end

end
