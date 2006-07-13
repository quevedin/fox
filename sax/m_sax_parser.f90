module m_sax_parser
!
! Basic module to parse XML in the SAX spirit.
!

use FoX_common, only: dictionary_t, parse_string_to_dict, destroy_dict, reset_dict, len, get_key, get_value
use m_common_array_str, only: str_vs, vs_str
use m_common_elstack          ! For element nesting checks
use m_sax_dtd, only : parse_dtd
use m_sax_reader
use m_sax_debug, only: debug
use m_sax_fsm, only: fsm_t, init_fsm, reset_fsm, destroy_fsm, evolve_fsm
use m_sax_fsm, only: END_OF_TAG, OPENING_TAG, SINGLE_TAG, CDATA_SECTION_TAG
use m_sax_fsm, only: CLOSING_TAG, COMMENT_TAG, DTD_TAG, PI_TAG
use m_sax_fsm, only: CHUNK_OF_PCDATA, QUIET, EXCEPTION, END_OF_DOCUMENT
use m_sax_namespaces, only: checkNamespaces, getnamespaceURI, checkEndNamespaces, invalidNS
use m_sax_error, only: sax_error_t, build_error_info, WARNING_CODE, SEVERE_ERROR_CODE, default_error_handler

implicit none

private

!
!  XML file handle
!
type, public :: xml_t
private
      type(file_buffer_t)  :: fb
      type(fsm_t)          :: fx
      character(len=200)   :: path_mark
end type xml_t

public :: xml_parse
public :: open_xmlfile, close_xmlfile
public :: endfile_xmlfile, rewind_xmlfile
public :: eof_xmlfile, sync_xmlfile
public :: xml_char_count
public :: xml_path, xml_mark_path, xml_get_path_mark
public :: xml_name, xml_attributes

CONTAINS  !=============================================================

subroutine open_xmlfile(fname,fxml,iostat,record_size)
  character(len=*), intent(in)      :: fname
  integer, intent(out)              :: iostat
  type(xml_t), intent(out)          :: fxml
  integer, intent(in), optional     :: record_size
  
  call open_file(fname,fxml%fb,iostat,record_size)
  call init_fsm(fxml%fx)
  fxml%path_mark = ""

end subroutine open_xmlfile
!-------------------------------------------------------------------------

subroutine rewind_xmlfile(fxml)
  type(xml_t), intent(inout) :: fxml
  
  call rewind_file(fxml%fb)
  call reset_fsm(fxml%fx)
  fxml%path_mark = ""
  
end subroutine rewind_xmlfile

!-----------------------------------------
subroutine endfile_xmlfile(fxml)
  type(xml_t), intent(inout) :: fxml

  call mark_eof_file(fxml%fb) 

end subroutine endfile_xmlfile

!-----------------------------------------
subroutine close_xmlfile(fxml)
  type(xml_t), intent(inout) :: fxml
  
  call close_file_buffer(fxml%fb)
  call destroy_fsm(fxml%fx) 
  fxml%path_mark = ""

end subroutine close_xmlfile

!-----------------------------------------
subroutine sync_xmlfile(fxml,iostat)
  type(xml_t), intent(inout) :: fxml
  integer, intent(out)       :: iostat
  
  call sync_file(fxml%fb,iostat)
  ! Do not reset fx: that's the whole point of synching.
  
end subroutine sync_xmlfile

!----------------------------------------------------
function eof_xmlfile(fxml) result (res)
  type(xml_t), intent(in)          :: fxml
  logical                          :: res
  
  res = eof_file(fxml%fb)
  
end function eof_xmlfile
!
!----------------------------------------------------
!----------------------------------------------------
function xml_char_count(fxml) result (nc)
  type(xml_t), intent(in)          :: fxml
  integer                          :: nc
  nc = nchars_processed(fxml%fb)
end function xml_char_count
!
!----------------------------------------------------
!

recursive subroutine xml_parse(fxml, begin_element_handler,    &
                           end_element_handler,             &
                           start_prefix_handler,            &
                           end_prefix_handler,              &
                           pcdata_chunk_handler,            &
                           cdata_section_handler,            &
                           comment_handler,                 &
                           processing_instruction_handler,  &
                           error_handler,                   &
                           signal_handler,                  &
                           verbose,                         &
                           start_document_handler,          & 
                           end_document_handler)   

type(xml_t), intent(inout), target  :: fxml

optional                            :: begin_element_handler
optional                            :: end_element_handler
optional                            :: start_prefix_handler
optional                            :: end_prefix_handler
optional                            :: pcdata_chunk_handler
optional                            :: cdata_section_handler
optional                            :: comment_handler
optional                            :: processing_instruction_handler
optional                            :: error_handler
optional                            :: signal_handler
logical, intent(in), optional       :: verbose
optional                            :: start_document_handler
optional                            :: end_document_handler

interface
   subroutine begin_element_handler(namespaceURI, localName, name, attributes)
   use FoX_common
   character(len=*), intent(in)     :: namespaceUri
   character(len=*), intent(in)     :: localName
   character(len=*), intent(in)     :: name
   type(dictionary_t), intent(in)   :: attributes
   end subroutine begin_element_handler

   subroutine end_element_handler(namespaceURI, localName, name)
   character(len=*), intent(in)     :: namespaceURI
   character(len=*), intent(in)     :: localName
   character(len=*), intent(in)     :: name
   end subroutine end_element_handler

   subroutine start_prefix_handler(namespaceURI, prefix)
   character(len=*), intent(in) :: namespaceURI
   character(len=*), intent(in) :: prefix
   end subroutine start_prefix_handler

   subroutine end_prefix_handler(prefix)
   character(len=*), intent(in) :: prefix
   end subroutine end_prefix_handler

   subroutine pcdata_chunk_handler(chunk)
   character(len=*), intent(in) :: chunk
   end subroutine pcdata_chunk_handler

   subroutine cdata_section_handler(chunk)
     character(len=*), intent(in) :: chunk
   end subroutine cdata_section_handler

   subroutine comment_handler(comment)
   character(len=*), intent(in) :: comment
   end subroutine comment_handler

   subroutine processing_instruction_handler(name, content, attributes)
     use FoX_common
     character(len=*), intent(in)     :: name
     character(len=*), intent(in)     :: content
     type(dictionary_t), intent(in)   :: attributes
   end subroutine processing_instruction_handler

   subroutine error_handler(error_info)
   use m_sax_error
   type(sax_error_t), intent(in)            :: error_info
   end subroutine error_handler

   subroutine signal_handler(code)
   logical, intent(out) :: code
   end subroutine signal_handler

   subroutine start_document_handler()   
   end subroutine start_document_handler 

   subroutine end_document_handler()     
   end subroutine end_document_handler   

end interface

character(len=1)       :: c
integer                :: iostat

integer                :: signal, dummy, s, i, n

character, allocatable :: name(:), oldname(:)

logical                :: have_begin_handler, have_end_handler, &
                          have_start_prefix_handler, have_end_prefix_handler, &
                          have_pcdata_handler, have_comment_handler, &
                          have_cdata_handler, &
                          have_processing_instruction_handler, &
                          have_error_handler, have_signal_handler, &
                          have_start_document_handler, have_end_document_handler
 
logical                :: pause_signal
logical                :: error_found

type(sax_error_t)            :: error_info
type(file_buffer_t), pointer :: fb
type(fsm_t), pointer         :: fx

have_begin_handler = present(begin_element_handler)
have_end_handler = present(end_element_handler)
have_start_prefix_handler = present(start_prefix_handler)
have_end_prefix_handler = present(end_prefix_handler)
have_pcdata_handler = present(pcdata_chunk_handler)
have_cdata_handler = present(cdata_section_handler)
have_comment_handler = present(comment_handler)
have_processing_instruction_handler = present(processing_instruction_handler)
have_error_handler = present(error_handler)
have_signal_handler = present(signal_handler)
have_start_document_handler = present(start_document_handler)  
have_end_document_handler = present(end_document_handler)      

fb => fxml%fb
fx => fxml%fx
if (present(verbose)) then
   debug = verbose                 ! For m_converters
   fx%debug = verbose              ! job-specific flag
endif

if (fx%debug) print *, " Entering xml_parse..."
if (have_start_document_handler) call start_document_handler()

!---------------------------------------------------------------------
do

      call evolve_fsm(fx, fb, signal)
      error_found = .false.

      if (fx%debug) print *, c, " ::: ", trim(fx%action)

      if(allocated(name)) deallocate(name)
      if(allocated(oldname)) deallocate(oldname)

      if (signal == END_OF_TAG) then
         !
         ! We decide whether we have ended an opening tag or a closing tag
         !
         if (fx%context == OPENING_TAG) then
            allocate(name(size(fx%element_name)))
            name = fx%element_name
            if (fx%debug) print *, "We have found an opening tag"
            if (fx%root_element_seen) then
               if (str_vs(name) == str_vs(fx%root_element_name)) then
                  call build_error_info(error_info, &
                  "Duplicate root element: " // str_vs(name), &
                  line(fb),column(fb),fx%element_stack,SEVERE_ERROR_CODE)
                  if (have_error_handler) then
                     call error_handler(error_info)
                  else
                     call default_error_handler(error_info)
                  endif
               endif
               if (is_empty(fx%element_stack)) then
                  call build_error_info(error_info, &
                  "Opening tag beyond root context: " // str_vs(name), &
                  line(fb),column(fb),fx%element_stack,SEVERE_ERROR_CODE)
                  if (have_error_handler) then
                     call error_handler(error_info)
                  else
                     call default_error_handler(error_info)
                  endif
               endif
            else
               allocate(fx%root_element_name(size(name)))
               fx%root_element_name = name
               fx%root_element_seen = .true.
            endif
            call push_elstack(str_vs(name),fx%element_stack)
            call destroy_dict(fx%attributes)
            call parse_string_to_dict(str_vs(fx%pcdata), fx%attributes, s)
            call checkNamespaces(fx%attributes, fx%nsDict, &
                 len(fx%element_stack), start_prefix_handler)
            if (getURIofQName(fxml,str_vs(name))==invalidNS) then
               ! no namespace was found for the current element
               call build_error_info(error_info, &
                    "No namespace mapped to prefix at", &
                    line(fb),column(fb),fx%element_stack,SEVERE_ERROR_CODE)
               if (have_error_handler) then
                  call error_handler(error_info)
               else
                  call default_error_handler(error_info)
               endif
            endif
            if (have_begin_handler) then 
               call begin_element_handler(getURIofQName(fxml, str_vs(name)), &
                                          getlocalNameofQName(str_vs(name)), &
                                          str_vs(name), fx%attributes)
            endif

         else if (fx%context == CLOSING_TAG) then
            allocate(name(size(fx%element_name)))
            name = fx%element_name
            if (fx%debug) print *, "We have found a closing tag"
            if (is_empty(fx%element_stack)) then
               call build_error_info(error_info, &
                  "Nesting error: End tag: " // str_vs(name) //  &
                  " does not match -- too many end tags", &
                  line(fb),column(fb),fx%element_stack,SEVERE_ERROR_CODE)
               if (have_error_handler) then
                  call error_handler(error_info)
               else
                  call default_error_handler(error_info)
               endif
            else
               allocate(oldname(len(get_top_elstack(fx%element_stack))))
               oldname = vs_str(get_top_elstack(fx%element_stack))
               if (all(oldname == name)) then
                  if (have_end_handler) then
                     call end_element_handler(getURIofQName(fxml, str_vs(name)), &
                                              getlocalnameofQName(str_vs(name)), &
                                              str_vs(name))
                  endif
                  call checkEndNamespaces(fx%nsDict, len(fx%element_stack), &
                       end_prefix_handler)
                  dummy = len(pop_elstack(fx%element_stack))
               else
                  call build_error_info(error_info, &
                       "Nesting error: End tag: " // str_vs(name) //  &
                       ". Expecting end of : " // str_vs(oldname), &
                       line(fb),column(fb),fx%element_stack,SEVERE_ERROR_CODE)
                  if (have_error_handler) then
                     call error_handler(error_info)
                  else
                     call default_error_handler(error_info)
                  endif
               endif
            endif
         else if (fx%context == SINGLE_TAG) then
            allocate(name(size(fx%element_name)))
            name = fx%element_name
            if (fx%debug) print *, "We have found a single (empty) tag: ", &
                 str_vs(name)
            if (fx%root_element_seen) then
               if (str_vs(name) == str_vs(fx%root_element_name)) then
                  call build_error_info(error_info, &
                  "Duplicate root element: " // str_vs(name), &
                  line(fb),column(fb),fx%element_stack,SEVERE_ERROR_CODE)
                  if (have_error_handler) then
                     call error_handler(error_info)
                  else
                     call default_error_handler(error_info)
                  endif
               endif
               if (is_empty(fx%element_stack)) then
                  call build_error_info(error_info, &
                  "Opening tag beyond root context: " // str_vs(name), &
                  line(fb),column(fb),fx%element_stack,SEVERE_ERROR_CODE)
                  if (have_error_handler) then
                     call error_handler(error_info)
                  else
                     call default_error_handler(error_info)
                  endif
               endif
            else
               allocate(fx%root_element_name(size(name)))
               fx%root_element_name = name
               fx%root_element_seen = .true.
            endif
            !
            ! Push name on to stack to reveal true xpath
            !
            call push_elstack(str_vs(name),fx%element_stack)
            call destroy_dict(fx%attributes)
            call parse_string_to_dict(str_vs(fx%pcdata), fx%attributes, s)
            call checkNamespaces(fx%attributes, fx%nsDict, &
                 len(fx%element_stack), start_prefix_handler)
            if (getURIofQName(fxml,str_vs(name))==invalidNS) then
               ! no namespace was found for the current element
               call build_error_info(error_info, &
                    "No namespace mapped to prefix at", &
                    line(fb),column(fb),fx%element_stack,SEVERE_ERROR_CODE)
               if (have_error_handler) then
                  call error_handler(error_info)
               else
                  call default_error_handler(error_info)
               endif
            endif
            if (have_begin_handler) then
               if (fx%debug) print *, "--> calling begin_element_handler..."
               call begin_element_handler(getURIofQName(fxml, str_vs(name)), &
                                          getlocalNameofQName(str_vs(name)), &
                                          str_vs(name), fx%attributes)
            endif
            if (have_end_handler) then
               if (fx%debug) print *, "--> ... and end_element_handler."
               call end_element_handler(getURIofQName(fxml, str_vs(name)), &
                                        getlocalNameofQName(str_vs(name)), &
                                        str_vs(name))
            endif
            call checkEndNamespaces(fx%nsDict, len(fx%element_stack), &
                 end_prefix_handler)
            dummy = len(pop_elstack(fx%element_stack))

         else if (fx%context == CDATA_SECTION_TAG) then

            if (fx%debug) print *, "We found a CDATA section"
            if (is_empty(fx%element_stack)) then
               if (fx%debug) print *, &
                   "... Warning: CDATA section outside element context"
            else
              if (have_cdata_handler) then
                call cdata_section_handler(str_vs(fx%pcdata))
              elseif (have_pcdata_handler) then
                call pcdata_chunk_handler(str_vs(fx%pcdata))
              endif
            endif

         else if (fx%context == COMMENT_TAG) then

            if (fx%debug) print *, "We found a comment tag"
            if (have_comment_handler)  &
                 call comment_handler(str_vs(fx%pcdata))

         else if (fx%context == DTD_TAG) then

            if (fx%debug) print *, "We found a DTD"
            call parse_dtd(str_vs(fx%pcdata), fx%entities)

         else if (fx%context == PI_TAG) then

           if (fx%debug) print *, "We found a Processing Instruction"
           allocate(name(size(fx%element_name)))
           name = fx%element_name
           call destroy_dict(fx%attributes)
           call parse_string_to_dict(str_vs(fx%pcdata), fx%attributes, s)
           ! expand entities ...?FIXME
           ! FIXME we should record XML version, encoding & standaloneness
           if (str_vs(name) == 'xml') then
             if (.not.fx%xml_decl_ok) then 
               call build_error_info(error_info, &
                    "XML declaration found after beginning of document.", &
                    line(fb),column(fb),fx%element_stack,SEVERE_ERROR_CODE)
               error_found = .true.
             else
               if (s > 0) then
                 call build_error_info(error_info, &
                      "Invalid XML declaration found.", &
                      line(fb),column(fb),fx%element_stack,SEVERE_ERROR_CODE)
                 error_found = .true.
               else
                 n = len(fx%attributes)
                 if (n == 0) then
                   call build_error_info(error_info, &
                        "No version found in XML declaration.", &
                        line(fb),column(fb),fx%element_stack,SEVERE_ERROR_CODE)
                   error_found = .true.
                 elseif (get_key(fx%attributes, 1) /= 'version') then
                   call build_error_info(error_info, &
                        "No version found in XML declaration.", &
                        line(fb),column(fb),fx%element_stack,SEVERE_ERROR_CODE)
                   error_found = .true.
                 endif
                 if (n == 2) then
                   if (get_key(fx%attributes, 2) /= 'encoding' .and. &
                       get_key(fx%attributes, 2) /= 'standalone') then
                     call build_error_info(error_info, &
                          "Invalid attribute in XML declaration.", &
                          line(fb),column(fb),fx%element_stack,WARNING_CODE)
                     error_found = .true.
                   endif
                 elseif (n == 3) then
                   if (get_key(fx%attributes, 2) /= 'standalone') then
                     call build_error_info(error_info, &
                          "Invalid attribute in XML declaration.", &
                          line(fb),column(fb),fx%element_stack,WARNING_CODE)
                     error_found = .true.
                   endif
                 elseif (n > 3) then
                   call build_error_info(error_info, &
                        "Invalid attribute in XML declaration.", &
                        line(fb),column(fb),fx%element_stack,WARNING_CODE)
                   error_found = .true.
                 endif
               endif
             endif
           endif
           if (error_found) then
             if (have_error_handler) then
               call error_handler(error_info)
             else
               call default_error_handler(error_info)
             endif
           endif
           if (have_processing_instruction_handler)  &
                call processing_instruction_handler(str_vs(name), &
                str_vs(fx%pcdata), fx%attributes)
           call reset_dict(fx%attributes)

         else

            ! do nothing

         endif

       else if (signal == CHUNK_OF_PCDATA) then

         if (fx%debug) write(*,'(a)'), "We found a chunk of PCDATA"
         if (have_pcdata_handler) &
              call pcdata_chunk_handler(str_vs(fx%pcdata))
         
       else if (signal == EXCEPTION) then
         call build_error_info(error_info, fx%action, &
              line(fb),column(fb),fx%element_stack,SEVERE_ERROR_CODE)
         if (have_error_handler) then
           call error_handler(error_info)
         else
           call default_error_handler(error_info)
         endif
         
       else if (signal == END_OF_DOCUMENT) then
         if (.not. is_empty(fx%element_stack) .or. &
           .not. fx%root_element_seen ) then
           call build_error_info(error_info, &
                "Early end of file.", &
                line(fb),column(fb),fx%element_stack,SEVERE_ERROR_CODE)
           if (have_error_handler) then
             call error_handler(error_info)
           else
             call default_error_handler(error_info)
           endif
         endif
         if (have_end_document_handler) call end_document_handler()
         call endfile_xmlfile(fxml)  ! Mark it as eof
         exit
         
       else if (signal /= QUIET) then
         ! QUIET, do nothing
         if (have_signal_handler) then
           call signal_handler(pause_signal)
           if (pause_signal) exit
         endif
       endif
       
     enddo

end subroutine xml_parse

!-----------------------------------------
subroutine xml_path(fxml,path)
  type(xml_t), intent(in) :: fxml
  character(len=*), intent(out)  :: path
  
  path = get_elstack_signature(fxml%fx%element_stack)
  
end subroutine xml_path

!-----------------------------------------
subroutine xml_mark_path(fxml,path)
  !
  ! Marks the current path
  !
  type(xml_t), intent(inout) :: fxml
  character(len=*), intent(out)  :: path
  
  fxml%path_mark = get_elstack_signature(fxml%fx%element_stack)
  path = fxml%path_mark
  
end subroutine xml_mark_path

!-----------------------------------------
subroutine xml_get_path_mark(fxml,path)
  !
  ! Returns the currently markd path (or an empty string if there are no marks)
  !
  type(xml_t), intent(in)        :: fxml
  character(len=*), intent(out)  :: path
  
  path = fxml%path_mark
  
end subroutine xml_get_path_mark

!-----------------------------------------
subroutine xml_name(fxml,name)
  type(xml_t), intent(in) :: fxml
  character(len=*), intent(out)  :: name
  
  name = str_vs(fxml%fx%element_name)
  
end subroutine xml_name
!-----------------------------------------
subroutine xml_attributes(fxml,attributes)
  type(xml_t), intent(in) :: fxml
  type(dictionary_t), intent(out)  :: attributes
  
  attributes = fxml%fx%attributes
  
end subroutine xml_attributes

  pure function getURIofQName(fxml, qname) result(URI)
    type(xml_t), intent(in) :: fxml
    character(len=*), intent(in) :: qName
    character(len=URIlength(fxml, qname)) :: URI
    
    integer :: n
    character, dimension(:), allocatable :: prefix
    n = index(QName, ':')
    if (n > 0) then
       allocate(prefix(n-1))
       prefix = transfer(QName(1:n-1), prefix)
       URI = getnamespaceURI(fxml%fx%nsDict, prefix)
       deallocate(prefix)
    else
       URI = getnamespaceURI(fxml%fx%nsDict)
    endif

  end function getURIofQName
  
  pure function URIlength(fxml, qname) result(l_u)
    type(xml_t), intent(in) :: fxml
    character(len=*), intent(in) :: qName
    integer :: l_u
    integer :: n
    character, dimension(:), allocatable :: prefix
    n = index(QName, ':')
    if (n > 0) then
       allocate(prefix(n-1))
       prefix = transfer(QName(1:n-1), prefix)
       l_u = len(getnamespaceURI(fxml%fx%nsDict, prefix))
       deallocate(prefix)
    else
       l_u = len(getnamespaceURI(fxml%fx%nsDict))
    endif
  end function URIlength

  pure function getLocalNameofQName(qname) result(localName)
    character(len=*), intent(in) :: qName
    character(len=len(QName)-index(QName,':')) :: localName
    
    localName = QName(index(QName,':')+1:)
  end function getLocalNameofQName

end module m_sax_parser
