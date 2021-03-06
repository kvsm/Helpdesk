class Helpdesk < Sinatra::Base
  #Display the new trouble ticket form
  get '/help-me' do
    self.init_ctx
    if self.is_user_logged_in && @rolename == 'requester'
      rec = @db[:users].find('username' => @username).limit(1).first
      if rec != nil
        @phone = rec[:phone]
        @email = rec[:email]
        @display = rec[:display]
      end
    else
      @phone = @params[:phone] unless (@params[:phone] == nil || @params[:phone] == '')
      @email = @params[:email] unless (@params[:email] == nil || @params[:email] == '')
      @display = @params[:display] unless (@params[:display] == nil || @params[:display] == '')
    end
    erb :helpme
  end

  #Creates the new trouble ticket
  post '/help-me' do
    self.init_ctx
    self.generate_code

    @params[:status] = 'New'
    @params[:updatedat] = @params[:createdat] = Time.now.strftime(@datetimefmt)
    if @username != nil && @username != ''
      @params[:createdby] = @params[:updatedby] = @username
    end
    @params[:myguid] = SecureRandom.uuid
    @db[:requests].insert_one @params
    @db.close
    redirect '/'
  end


  #List all trouble tickets
  get '/tickets-list' do
    self.init_ctx
    if !self.is_user_logged_in()
      redirect '/login'
      return
    end

    @skip = 0
    if @skip != nil && @skip != ''
      @skip = @params[:skip].to_i
    end

    @criteria = {}
    if (@params[:code] != nil && @params[:code] != '') then @criteria[:code] = {  '$regex' => '.*' + Regexp.escape(@params[:code]) + '.*', '$options' => 'i' } end
    if (@params[:complaint] != nil && @params[:complaint] != '') then @criteria[:complaint] = { '$regex' => '.*' + Regexp.escape(@params[:complaint]) + '.*', '$options' => 'i' } end
    if (@params[:status] != nil && @params[:status] != '') then @criteria[:status] = {  '$regex' => '.*' + Regexp.escape(@params[:status]) + '.*', '$options' => 'i' } end

    @totalrowcount = 0
    if @rolename == 'requester'
      @criteria[:createdby] = @username
      #Helpdesk agents and admins can view the statuses of all requests
    end
    @totalrowcount = @list = @db[:requests].find(@criteria).count()
    @list = @db[:requests].find(@criteria, :sort => {'updatedat': -1}).skip(@skip).limit(@pagesize)

    @showpager = true

    erb :ticketslist
  end

  #Change the ticket status
  post '/ticket-status' do
    self.init_ctx

    @record = @db[:requests].find('code' => @params[:code]).limit(1).first;

    @record[:updatedat] = Time.now.strftime(@datetimefmt)
    @record[:updatedby] = @username
    @record[:status] = @params[:status]

    @db[:requests].update_one(
        {'code' => params[:code]},
        @record,
        {:upsert => false}
    )

    @db.close

    redirect '/tickets-list'
  end

  #Get info about a single trouble ticket
  get '/ticket-detail/:code' do
    self.init_ctx
    if !self.is_user_logged_in()
      redirect '/login'
      return
    end

    if @rolename == 'requester'
      @rec = @db[:requests].find('createdby' => @username, 'code' => @params[:code]).limit(1).first
      @personnel = []
    else
      @rec = @db[:requests].find('code' => @params[:code]).limit(1).first
      @personnel = @db[:personnel].find()
    end

    erb :ticketdetail
  end

  #Get info about a single trouble ticket
  post '/ticket-detail/:code' do
    self.init_ctx
    if !self.is_user_logged_in()
      redirect '/login'
      return
    end

    if @rolename == 'requester'
      @rec = @db[:requests].find('createdby' => @username, 'code' => @params[:code]).limit(1).first
      # @personnel = []
    else
      @rec = @db[:requests].find('code' => @params[:code]).limit(1).first
      # @personnel = @db[:personnel].find()
    end

    if @rec == nil
      redirect '/tickets-list'
      return
    end

    savedfields = ['name', 'phone', 'email', 'complaint', 'description', 'room', 'locationdescription', 'org', 'dept', 'building', 'floor']

    savedfields.each do |x|
      @rec[x] = @params[x]
    end


    @db[:requests].update_one(
        {'code' => params[:code]},
        @rec,
        {:upsert => false}
    )

    @db.close
    
    redirect ('/ticket-detail/' + @params[:code])
  end

  post '/comment-add/:ticket' do
    self.init_ctx
    if !self.is_user_logged_in()
      redirect '/login'
      return
    end

    if @rolename == 'requester'
      @rec = @db[:requests].find('createdby' => @username, 'code' => @params[:ticket]).limit(1).first
    else
      @rec = @db[:requests].find('code' => @params[:ticket]).limit(1).first
    end
    #TODO: Replace this drama queen of a code with a simple count check if we aren't using any of the record fields when posting
    if @rec == nil
      redirect '/'
      return #Is a return absolutely necessary?
    end

    @db[:requests].update_one(
        {'code' => params[:ticket]},
        {'$push' => {'comments' => {
            :txt => @params[:txt],
            :at => Time.now.strftime(@datetimefmt),
            :by => @username
        }}},
        {:upsert => false}
    )

    @db.close

    redirect '/ticket-detail/'+@params[:ticket]
  end

  post '/ticket-assign/:ticket' do
    self.init_ctx
    if !self.is_user_logged_in()
      redirect '/login'
      return
    end

    if ['helpdesk', 'admin'].include? @rolename
      @rec = @db[:requests].find('code' => @params[:ticket]).limit(1).first
    else
      redirect '/login'
      return
    end

    #TODO: Replace this drama queen of a code with a simple count check if we aren't using any of the record fields when posting
    if @rec == nil
      redirect '/'
      return #Is a return absolutely necessary?
    end

    @rec['assigned'] = @params[:assigned]
    @db[:requests].update_one(
        {'code' => @params[:ticket]},
        @rec,
        {:upsert => false}
    )

    @db.close

    redirect '/ticket-detail/'+@params[:ticket]
  end
end
