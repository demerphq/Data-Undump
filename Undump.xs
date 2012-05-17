#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

/*
    Grammar:

    INTEGER:        /-?(?:0|[1-9][0-9]+)/x
    FLOAT:          /-?(?:0|[1-9][0-9]+)\.([0-9]+)/x
    BAREWORD:       / [A-Za-z_]+ [0-9A-Za-z_]* /x
    Q_STRING:       /'(?:\\\\|\\'|.)*'/s
    QQ_STRING:      /"(?:\\x\{[A-Fa-f0-9]+\}|\\[0-6]{1,2}(?![0-6])|\\[0-6]{3}|\\.|.)*"/i
    SIMPLE_COMMA:   ','
    FAT_COMMA:      '=>'
    OPEN_HASH:      '{'
    CLOSE_HASH:     '}'
    OPEN_ARRAY:     '['
    CLOSE_ARRAY:    ']'
    UNDEF:          'undef'

    VALUE: UNDEF | INTEGER | FLOAT | QUOTED_STRING | HASH | ARRAY
    KEY: INTEGER | FLOAT | BAREWORD | QUOTED_STRING

    KEY_VALUE_LIST: (KEY FAT_COMMA VALUE (SIMPLE_COMMA KEY FAT_COMMA VALUE)*)?
    VALUE_LIST:     (VALUE (SIMPLE_COMMA VALUE)*)?

    HASH:           OPEN_HASH  KEY_VALUE_LIST CLOSE_HASH
    ARRAY:          OPEN_ARRAY VALUE_LIST     CLOSE_ARRAY
*/

#define TOKEN_ERROR         0
#define TOKEN_COMMA         1
#define TOKEN_OPEN          2
#define TOKEN_CLOSE         3
#define TOKEN_UNDEF         4
#define TOKEN_IV            5
#define TOKEN_NV            6
#define TOKEN_BAREWORD      7
#define TOKEN_Q_STRING      8
#define TOKEN_QQ_STRING     9
#define TOKEN_WS            10
#define TOKEN_BLESS         11
#define TOKEN_UNKNOWN       12

const char * const token_name[]= {
    "TOKEN_ERROR",
    "TOKEN_COMMA",
    "TOKEN_OPEN",
    "TOKEN_CLOSE",
    "TOKEN_UNDEF",
    "TOKEN_IV",
    "TOKEN_NV",
    "TOKEN_BAREWORD",
    "TOKEN_Q_STRING",
    "TOKEN_QQ_STRING",
    "TOKEN_WS",
    "TOKEN_BLESS",
    "TOKEN_UNKNOWN"
};

const char bareword_start[]= {
      0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0, 
      0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0, 
      0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0, 
      0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0, 
      0,  65,  66,  67,  68,  69,  70,  71,  72,  73,  74,  75,  76,  77,  78,  79, 
     80,  81,  82,  83,  84,  85,  86,  87,  88,  89,  90,   0,   0,   0,   0,  95, 
      0,  97,  98,  99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 
    112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122,   0,   0,   0,   0,   0, 
      0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0, 
      0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0, 
      0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0, 
      0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0, 
      0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0, 
      0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0, 
      0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0, 
      0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0, 
};

const char bareword_rest[]= {
      0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0, 
      0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0, 
      0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0, 
     48,  49,  50,  51,  52,  53,  54,  55,  56,  57,   0,   0,   0,   0,   0,   0, 
      0,  65,  66,  67,  68,  69,  70,  71,  72,  73,  74,  75,  76,  77,  78,  79, 
     80,  81,  82,  83,  84,  85,  86,  87,  88,  89,  90,   0,   0,   0,   0,  95, 
      0,  97,  98,  99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 
    112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122,   0,   0,   0,   0,   0, 
      0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0, 
      0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0, 
      0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0, 
      0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0, 
      0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0, 
      0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0, 
      0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0, 
      0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0
};

#define BAIL(pointer) STMT_START { \
    if(parse_start && pointer) *parse_start= pointer;\
    if(got) SvREFCNT_dec(got);  \
    if(got_key) SvREFCNT_dec(got_key);  \
    if(thing) SvREFCNT_dec(thing);  \
    return 0; \
} STMT_END

#define DEPTH(depth,token) ( ( (depth) * 4 ) + ( ( (token) == TOKEN_OPEN || (token) == TOKEN_BLESS ) - ( ( token ) == TOKEN_CLOSE ) ) * 2 )

#define MYDEBUG 0

#define SHOW_POSITION( depth, token, token_start, pointer, parse_end, show_len ) STMT_START {\
    int remaining= (parse_end) - (pointer); \
    int token_len= (pointer) - (token_start); \
    int backup_len=0;\
    const char *backup_pos;\
    if (*parse_start < token_start) { \
        backup_len= token_start - *parse_start; \
        if (backup_len > show_len) { \
            backup_len= show_len; \
        } \
        backup_pos= token_start - backup_len; \
    } else { \
        backup_pos= 0; \
    } \
    warn("%*sprior:'%.*s'\n"                \
         "%*stoken:'%.*s'%s\n"              \
         "%*sto-go:'%.*s'%s\n\n",             \
        DEPTH((depth),(token)), "",         \
        backup_len, backup_pos,             \
        DEPTH((depth),(token)), "",         \
        ( ( token_len > (show_len) ) ? (show_len) : token_len) , (token_start), \
        ( ( token_len > (show_len) ) ? "..." : ""), \
        DEPTH((depth),(token)), "", \
        ( ( remaining > (show_len) ) ? (show_len) : remaining ) , (pointer), \
        ( ( remaining > (show_len) ) ? "..." : "") \
    ); \
} STMT_END

#define PANIC(depth,token,token_start,pointer,parse_end,X) STMT_START { \
    if (MYDEBUG) { \
        warn("%*s%s\n",DEPTH((depth),(token)) , "", (X)); \
        SHOW_POSITION((depth),(token), (token_start), (pointer), (parse_end), 32); \
    } \
    sv_setpvf( ERRSV, "%s\n", (X) ); \
    BAIL((pointer));\
} STMT_END

#define PANICf1(depth,token,token_start,pointer,parse_end,F,X) STMT_START { \
    if (MYDEBUG) { \
        warn("%*s" F "\n",DEPTH((depth),(token)),"", (X)); \
        SHOW_POSITION((depth), (token),(token_start),  (pointer), (parse_end), 32); \
    }\
    sv_setpvf( ERRSV, F "\n", (X) ); \
    BAIL((pointer));\
} STMT_END

#define PANICf2(depth,token,token_start,pointer,parse_end,F,X,Y) STMT_START { \
    if (MYDEBUG) { \
        warn("%*s" F "\n",DEPTH((depth),(token)),"", (X),(Y)); \
        SHOW_POSITION((depth), (token), (token_start), (pointer), (parse_end), 32); \
    } \
    sv_setpvf( ERRSV, F "\n", (X), (Y)); \
    BAIL((pointer));\
} STMT_END

#define ERROR(depth,token,token_start,pointer,parse_end,X) STMT_START { \
    if (MYDEBUG>1) { \
        warn("%*s%s\n",DEPTH((depth),(token)) , "", (X)); \
        SHOW_POSITION((depth),(token), (token_start), (pointer), (parse_end), 32); \
    } \
    sv_setpvf( ERRSV, "%s\n", (X) ); \
    BAIL((pointer));\
} STMT_END

#define ERRORf1(depth,token,token_start,pointer,parse_end,F,X) STMT_START { \
    if (MYDEBUG>1) { \
        warn("%*s" F "\n",DEPTH((depth),(token)),"", (X)); \
        SHOW_POSITION((depth), (token), (token_start), (pointer), (parse_end), 32); \
    } \
    sv_setpvf( ERRSV, F "\n", (X) ); \
    BAIL((pointer));\
} STMT_END

#define ERRORf2(depth,token,token_start,pointer,parse_end,F,X,Y) STMT_START { \
    if (MYDEBUG>1) { \
        warn("%*s" F "\n",DEPTH((depth),(token)),"", (X),(Y)); \
        SHOW_POSITION((depth), (token), (token_start), (pointer), (parse_end), 32); \
    } \
    sv_setpvf( ERRSV, F "\n", (X), (Y)); \
    BAIL((pointer));\
} STMT_END

#define SHOW_TOKEN(depth, token, token_start, pointer) \
    if (MYDEBUG>1) warn("%*s%-2d %*s %.*s\n", DEPTH((depth), (token)), "", \
         token, -20,  token_name[((token)<TOKEN_UNKNOWN) ? (token) : TOKEN_UNKNOWN ],(int)((pointer) - (token_start)), (token_start))


#define COND_ISWHITE(ch) ( (ch) == ' ' || (ch) == '\n' || (ch) == '\t' || (ch) == '\r' )
#define CASE_ISWHITE ' ': case '\n': case '\t': case '\r' 
#define EAT_WHITE(p) STMT_START { while ( COND_ISWHITE(*p) ) { p++; } } STMT_END
#define DONE_KEY_break                      \
        want_key= 0;                        \
        allow_comma= 1;                     \
        break
#define DONE_KEY_SIMPLE_break               \
        key= token_start;                   \
        key_len= parse_ptr - token_start;   \
        DONE_KEY_break                      

SV* _undump(pTHX_ const char **parse_start, const char const *parse_end, char obj_char, unsigned int depth);


/* recursively undump a DD style dump 
 * 
 * If called with an obj_char then we are building an object of that type, otherwise we are searching for
 * a new value. When we encounter a '[' we gobble it up and then call the child with '[' as the obj_char
 * where it then parses until it encounters a ']' which it eats, and then return whatever it built.
 *
 * We restrict to objects nested 100 items deep.
 *
 * If anything bogus in the input stream is encountered we free everything created so far, and return 0 
 * to unwind. We update the parents parse_ptr via the parse_start pointer as necessary to pass back how
 * far we have consumed.
 * 
 * Returns either an SV or NULL indicating an error.
 *
 */

SV* _undump(pTHX_ const char **parse_start, const char const *parse_end, char obj_char, unsigned int depth) {
    const char *parse_ptr= *parse_start;
    char token= TOKEN_ERROR;
    char want_key= 0;
    char allow_comma= 0;
    char require_fat_comma= 0;
    char stop_char;
    char ch;
    const char *key;
    STRLEN key_len;
    SV *thing= 0;
    SV *got_key= 0;
    SV *got= 0;
    const char *token_start= *parse_start;
    const char *first_escape= 0;

    if (depth > 100) {
        PANIC(depth,token,token_start,parse_ptr,parse_end,"Structure is nested too deep");
    }

    if (!obj_char) {
        stop_char= 0;
    } else if (obj_char == '[') {
        thing= (SV*)newAV();
        stop_char= ']';
    } else if (obj_char == '{') {
        key= 0;
        key_len= 0;
        thing= (SV*)newHV();
        want_key= 1;
        stop_char= '}';
    } else {
        PANICf1(depth,token,token_start,parse_ptr,parse_end, "Unknown obj char '%c'", obj_char);        
    }

  REPARSE:
    while (parse_ptr < parse_end) {
        /* warn("want_key: %d require_fat_comma: %d allow_comma: %d\n", want_key, require_fat_comma, allow_comma); */
        token_start= parse_ptr;
        token= TOKEN_ERROR;
        ch= *(parse_ptr++);
        switch (ch) {
            case CASE_ISWHITE:
                EAT_WHITE(parse_ptr);
                goto REPARSE;
            case '=':
                if ( *parse_ptr != '>' ) {
                    ERROR(depth,token,token_start,parse_ptr,parse_end,"Encountered assignment '=' or unterminated fat comma '=>'");
                }
                require_fat_comma = 0;
                parse_ptr++;
                /* fallthrough */
            case ',': 
                /* comma */
                if ( require_fat_comma ) {
                    ERROR(depth,token,token_start,parse_ptr,parse_end,"expected fat comma after bareword");
                }
                else if ( ! allow_comma ) {
                    ERRORf2(depth,token,token_start,parse_ptr,parse_end,"unexpected %s when expecting a %s",
                        (ch=='=' ? "fat comma" : "comma"),(want_key ? "key" : "value"));
                }
                allow_comma = 0;
                goto REPARSE;
            case '$': 
            case '%': 
            case '@': 
                parse_ptr--;
                ERROR(depth,token,token_start,parse_ptr,parse_end,"Encountered variable in input. This is not eval - can not undump code");
            case '{':
            case '[':
                token= TOKEN_OPEN;                
                break;
            case ']':
            case '}':
                token= TOKEN_CLOSE;
                break;
            case '\'':
                first_escape= 0;
                while (parse_ptr < parse_end && *parse_ptr != '\'') {
                    /* check if its a valid escape */
                    if (*parse_ptr == '\\' && (parse_ptr[1] == '\\' || parse_ptr[1] == '\'')) { 
                        if (!first_escape) 
                            first_escape= parse_ptr;
                        parse_ptr++;
                    }
                    parse_ptr++;
                    
                }
                if (parse_ptr >= parse_end) {
                    ERROR(depth,token,token_start,parse_ptr,parse_end,"unterminated single quoted string");
                }
                assert(*parse_ptr == ch);
                parse_ptr++; /* skip over the trailing quote */
                token= TOKEN_Q_STRING;
                break;
            case '\"':
                /* quoted */
                first_escape= 0;
                while (parse_ptr < parse_end && *parse_ptr != ch) {
                    if (*parse_ptr == '\\') { /* if its an escape pull off the backslash */
                        if (!first_escape) 
                            first_escape= parse_ptr;
                        parse_ptr++;
                    } else if (*parse_ptr == '$' || *parse_ptr == '@') {
                        ERROR(depth,token,token_start,parse_ptr,parse_end,"Unescaped '$' and '@' are illegal in double quoted strings");
                    }
                    parse_ptr++;
                }
                if (parse_ptr >= parse_end) {
                    ERROR(depth,token,token_start,parse_ptr,parse_end,"unterminated double quoted string");
                }
                assert(*parse_ptr == ch);
                parse_ptr++; /* skip over the trailing quote */
                token= TOKEN_QQ_STRING;
                break;
            case '-':
                ch= *parse_ptr;
                if ( '0' == ch ) {
                    parse_ptr++;
                    if (*parse_ptr != '.') {
                        ERROR(depth,token,token_start,parse_ptr,parse_end,"Negative number start with a zero that is not fractional is illegal");
                    }
                    goto DO_DECIMAL;
                } else if ( '1' <= ch && ch <= '9' ) {
                    parse_ptr++;
                } else {
                    ERROR(depth,token,token_start,parse_ptr,parse_end,"bare '-' only allowed to signify negative number");                        
                }
                goto DO_NUMBER;
            case '0':
                if ( parse_ptr < parse_end && ('0' <= *parse_ptr && *parse_ptr <= '9')) {
                    ERROR(depth,token,token_start,parse_ptr,parse_end,"Zero may not be followed by another digit at the start of a number");
                }
            case '1':
            case '2':
            case '3':
            case '4':
            case '5':
            case '6':
            case '7':
            case '8':
            case '9':
              DO_NUMBER:
                /* number */
                ch= *parse_ptr;         
                while ( '0' <= ch && ch <= '9' ) {
                    ch= *(++parse_ptr);
                }
                if ( ch == '.' ) {
                  DO_DECIMAL:
                    ch= *(++parse_ptr);
                    if ( '0' <= ch && ch <= '9' ) {
                        ch= *(++parse_ptr);
                    } else {
                        ERROR(depth,token,token_start,parse_ptr,parse_end,"Unexpected end of floating point number after decimal point");
                    }
                    while ('0' <= ch && ch <= '9') {
                        ch= *(++parse_ptr);
                    }
                    token= TOKEN_NV;
                } else {
                    token= TOKEN_IV;
                }
                break;
            default: 
                if (bareword_start[(U8)ch]) {
                    ch= *parse_ptr;
                    while ( bareword_rest[(U8)ch] ) {
                        ch= *(++parse_ptr);
                    }
                } else {
                    parse_ptr--;
                    PANICf2(depth,token,token_start,parse_ptr,parse_end,
                        "Unexpected character '%c' codepoint 0x%02x while parsing bareword",ch,ch);
                }
                /* for some reason all the interesting keywords are 5 characters long */
                if ( 5 == (parse_ptr - token_start) ) {
                    if ( 
                         'b' == token_start[0] && 
                         'l' == token_start[1] &&
                         'e' == token_start[2] &&
                         's' == token_start[3] &&
                         's' == token_start[4]
                    ){
                        token= TOKEN_BLESS;
                    } else if ( 
                         'u' == token_start[0] && 
                         'n' == token_start[1] &&
                         'd' == token_start[2] &&
                         'e' == token_start[3] &&
                         'f' == token_start[4]
                    ){
                        token= TOKEN_UNDEF;
                    } else { 
                        token= TOKEN_BAREWORD;
                    }
                } else {
                    token= TOKEN_BAREWORD;
                }
        } /* switch */
        if (require_fat_comma) {
            ERROR(depth,token,token_start,parse_ptr,parse_end,"expected fat comma after bareword");
        } else if (allow_comma && token != TOKEN_CLOSE) {
            ERRORf1(depth,token,token_start,parse_ptr,parse_end,"Expecting comma got %s",token_name[token]);
        }
        SHOW_TOKEN(depth,token,token_start,parse_ptr);
        switch (token) {
            case TOKEN_BLESS:
                if ( *parse_ptr != '(') {
                    ERROR(depth,token,token_start,parse_ptr,parse_end,"expected a '(' after 'bless'");
                } else {
                    parse_ptr++;
                    /* ERROR(depth,token,token_start,parse_ptr,parse_end,"after bless("); */
                }
                if (want_key) {
                    ERRORf1(depth,token,token_start,parse_ptr,parse_end,"unexpected bless() call when expecting a key", ch);
                }
                ch= 0; /* flag for blessing */
            case TOKEN_OPEN:
                if (want_key) {
                    ERRORf1(depth,token,token_start,parse_ptr,parse_end,"unexpected open bracket '%c' when expecting a key", ch);
                }
                if (got) {
                    ERROR(depth,token,token_start,parse_ptr,parse_end,"Multiple objects in stream?");
                }
                got= _undump( aTHX_ &parse_ptr, parse_end, ch, depth+1);
                if (!got) {
                    BAIL(parse_ptr);
                } else {
                    if ( ch == 0 ) {
                        char quote;
                        HV *stash;
                        EAT_WHITE(parse_ptr);
                        if (*parse_ptr == ',') {
                            parse_ptr++;
                            EAT_WHITE(parse_ptr);
                        } else {
                            ERROR(depth,token,token_start,parse_ptr,parse_end,"expected a comma after object in bless()");
                        }
                        ch= *parse_ptr;
                        if ( ch != '\'' && ch != '\"') {
                            ERROR(depth,token,token_start,parse_ptr,parse_end,"Expected quoted class name after object in bless()");
                        }
                        quote = ch;
                        token_start= ++parse_ptr;
                        if (!bareword_start[(U8)*parse_ptr]) {
                            ERROR(depth,token,token_start,parse_ptr,parse_end,"Expected classname to start with [A-Za-z_]");
                        }
                        do { 
                            ch= *(++parse_ptr);
                            if (ch == ':') {
                                ch= *(++parse_ptr);
                                if (ch != ':') {
                                    ERROR(depth,token,token_start,parse_ptr,parse_end,"Single colon in class name?");
                                } else {
                                    ch= *(++parse_ptr);
                                }
                            }
                        } 
                        while (bareword_rest[(U8)ch]);
                        if (ch != quote) {
                            ERROR(depth,token,token_start,parse_ptr,parse_end,"Unterminated or corrupt classname");
                        } 

                        /* XXX: mortalize 'got; here? can this die? */
                        stash= gv_stashpvn(token_start, parse_ptr - token_start, 1);
                        if (!stash) {
                            PANIC(depth,token,token_start,parse_ptr,parse_end,"Failed to load stash");
                        }
                        ++parse_ptr; /* skip quote */
                        EAT_WHITE(parse_ptr); /* eat optional whitespace after quote */
                        ch= *parse_ptr; /* check we have a close paren */
                        if (ch != ')') {
                            ERRORf1(depth,token,token_start,parse_ptr,parse_end,"expecting a close paren for bless but got a '%c'",ch);
                        } else {
                            parse_ptr++;
                        }
                        /* and finally do the blessing */
                        if(0) do_sv_dump(0, Perl_debug_log, got, 0, 4, 0, 0);    
                        sv_bless(got,stash);
                        if(0) do_sv_dump(0, Perl_debug_log, got, 0, 4, 0, 0);    
                        
                    }
                    goto GOT_SV;
                }     
                /* unreached */           
                break;
            case TOKEN_CLOSE:
            {
                if (stop_char == ch) {
                    if (got_key || key) {
                        ERROR(depth,token,token_start,parse_ptr,parse_end,"Odd number of items in hash constructor");
                    }
                    *parse_start= parse_ptr;
                    return  newRV((SV *)thing);
                } else if (!stop_char) {
                    ERRORf1(depth,token,token_start,parse_ptr,parse_end,"Unexpected close bracket '%c'",ch);
                } else {
                    ERRORf2(depth,token,token_start,parse_ptr,parse_end,"Unexpected close '%c' while parsing %s",
                            ch, (stop_char == '}') ? "HASH" : "ARRAY");
                } 
                break;
            }
            case TOKEN_UNDEF:
                if (want_key) {
                    ERROR(depth,token,token_start,parse_ptr,parse_end,"got an undef when we wanted a key");
                }
                if (got) {
                    ERROR(depth,token,token_start,parse_ptr,parse_end,"Multiple objects in stream?");
                }
                got= newSV(0);
                goto GOT_SV;
                /* unreached */
                break;
                                
            case TOKEN_Q_STRING:
            case TOKEN_QQ_STRING:{
                /* nothing to unescape - we are done now */
                token_start++; /* skip the first quote */
                if ( !first_escape ) {
                    /* it didnt contain any escapes */
                    if ( want_key ) {
                        key= token_start;
                        key_len= parse_ptr - token_start - 1; /* remove trailing quote */
                        want_key= 0;
                        allow_comma= 1;
                        break;
                    }
                    if (got) {
                        ERROR(depth,token,token_start,parse_ptr,parse_end,"Multiple objects in stream?");
                    }
                    got= newSVpvn(token_start, parse_ptr - token_start - 1); /* remove trailing quote */                
                    goto GOT_SV;                
                } else {
                    /* contains escapes - so we have to unescape it */
                    STRLEN grok_len= 0;
                    I32 grok_flags= 0;
                    const char *grok_start;
                    char is_uni= 0;
                    char must_uni= 0;                  
                    char *new_str_begin;
                    char *new_str_end;
                    char *esc_read;
                    char *esc_write;
                    STRLEN new_len;
                                
                    if (got) {
                        ERROR(depth,token,token_start,parse_ptr,parse_end,"Multiple objects in stream?");
                    }
                    /* create a new SV with a copy of the raw escaped string in it - with octal
                       this is sufficient to guarantee enough space to unescape, with \x{} style
                       escapes things are more complicated */

                    got= newSVpvn(token_start, parse_ptr - token_start - 1); /* remove trailing quote */                
                    /* the sv now contains a copy of the unescaped string */ 

                    new_str_begin= SvPV(got, new_len);
                    new_str_end= new_str_begin + new_len;
                    esc_read= esc_write= new_str_begin + ( first_escape - token_start );
                    if (*esc_write != '\\') {
                        PANIC(depth,token,token_start,parse_ptr,parse_end,"when parsing quoted string failed start quote sanity check");
                    }
                    if (token == TOKEN_Q_STRING) {
                        do {
                            if (*esc_read == '\\' && (esc_read[1] == '\\' || esc_read[1] == '\'')) {
                                esc_read++;
                            }
                            *esc_write++ = *esc_read++;
                        } while (esc_read < new_str_end);
                    } else { /* TOKEN_QQ_STRING */
                        while (esc_read < new_str_end) {
                            U32 cp= *esc_read++;                            
                            if ( cp == '\\' ) {
                                if (esc_read >= new_str_end) {
                                    PANIC(depth,token,token_start,parse_ptr,parse_end,"ran off end of string");
                                }
                                ch= *esc_read++;
                                switch (ch) {
                                    case '0':
                                    case '1':
                                    case '2':
                                    case '3':
                                    case '4':
                                    case '5':
                                    case '6':
                                        /* first octal digit */
                                        grok_start= esc_read-1; /* it was advanced earlier */
                                        ch= *esc_read;
                                        if ('0' <= ch && ch <= '6') { 
                                            /* second octal digit */
                                            esc_read++;
                                            ch= *esc_read;
                                            if ('0' <= ch && ch <= '6') {
                                                /* third octal digit */
                                                esc_read++;
                                            }
                                        }
                                        grok_len= esc_read - grok_start;
                                        cp= grok_oct((char *)grok_start, &grok_len, &grok_flags, 0);
                                        break;
                                    case 'x':
                                        if (*esc_read != '{') {
                                            ERROR(depth,token,token_start,parse_ptr,parse_end,"truncated \\x{} sequence?");
                                        } else {
                                            esc_read++;
                                        }
                                        grok_start= esc_read;
                                        while (*esc_read && *esc_read != '}') esc_read++;
                                        if (*esc_read != '}') {
                                            ERROR(depth,token,token_start,parse_ptr,parse_end,"unterminated \\x{} in double quoted string");
                                        } else {
                                            grok_len= esc_read - grok_start;
                                            esc_read++; /* skip '}' */
                                        }
                                        /* warn("hex: %.*s\n", grok_len, grok_start); */
                                        if (grok_len) {
                                            cp= grok_hex((char *)grok_start, &grok_len, &grok_flags, 0);
                                        } else {
                                            ERROR(depth,token,token_start,parse_ptr,parse_end,"empty \\x{} escape?");
                                        }
                                        /* warn("cp: %d\n len: %d flags: %d", cp, grok_len, grok_flags); */
                                        if ( cp < 0x100 ) { /* otherwise it would be in octal */
                                            must_uni= 1;
                                        }
                                        if (cp>0x10FFFF) {
                                            ERRORf1(depth,token,token_start,parse_ptr,parse_end,"Illegal codepoint in \\x{%x}",cp);
                                        }
                                        break;
                                    /* printf-style backslashes, formfeeds, newlines, etc */
                                    case 'a': cp= '\007'; break; /* "\a" => "\\a", */
                                    case 'b': cp= '\b';   break; /* "\b" => "\\b", */
                                    case 'e': cp= '\033'; break; /* "\e" => "\\e", */
                                    case 'f': cp= '\f';   break; /* "\f" => "\\f", */
                                    case 'n': cp= '\n';   break; /* "\n" => "\\n", */
                                    case 'r': cp= '\r';   break; /* "\r" => "\\r", */
                                    case 't': cp= '\t';   break; /* "\t" => "\\t", */
                                    default:  cp= ch;     break; /* literal */
                                } /* switch on escape type */
                            } /* is an escape */
                            if (is_uni) {
                                sv_catpvf(got, "%c", cp);
                            } else if (cp < 256) {
                                *esc_write++= (char)cp;
                            } else {
                                SvCUR_set(got, esc_write - new_str_begin);
                                is_uni= 1;
                                sv_catpvf(got, "%c", cp);
                            }
                        } /* while */
                    }  /* TOKEN_Q_STRING or TOKEN_QQ_STRING */
                    if (!is_uni) {
                        SvCUR_set(got, esc_write - new_str_begin);
                        *esc_write++= 0;
                        if (must_uni && !is_uni) {
                            sv_utf8_upgrade(got);
                        }
                    }
                    if (want_key) {
                        /* we contain stuff that will be used as a hash key lookup */
                        got_key= got;   /* swap got over to the got_key var for later */
                        key= 0;         /* make sure we dont get confused about two keys */                   
                        got= 0;         /* clear got */
                        DONE_KEY_break;
                    } else {
                        /* and now do something with the SV */
                        goto GOT_SV;
                    }
                }
                /* not reached */
            }
            case TOKEN_BAREWORD:
                /* fallthrough */
                require_fat_comma= 1;
                if (want_key) {
                    DONE_KEY_SIMPLE_break;
                }
                if (got) {
                    ERROR(depth,token,token_start,parse_ptr,parse_end,"Multiple objects in stream?");
                }
                got= newSVpvn(token_start, parse_ptr - token_start);
                goto GOT_SV;
            case TOKEN_IV:{
                IV iv;
                
                /* fallthrough */
                if (want_key) {
                    DONE_KEY_SIMPLE_break;
                } 
                iv= 0;
                ch= parse_ptr - token_start;
                if (token_start[0] == '-') {
                    if ( ch < 12) {
                        token_start++;
                        switch (ch) {
                            case 11: iv -= (*token_start++ - '0') * 1000000000;
                            case 10: iv -= (*token_start++ - '0') * 100000000;
                            case  9: iv -= (*token_start++ - '0') * 10000000;
                            case  8: iv -= (*token_start++ - '0') * 1000000;
                            case  7: iv -= (*token_start++ - '0') * 100000;
                            case  6: iv -= (*token_start++ - '0') * 10000;
                            case  5: iv -= (*token_start++ - '0') * 1000;
                            case  4: iv -= (*token_start++ - '0') * 100;
                            case  3: iv -= (*token_start++ - '0') * 10;
                            case  2: iv -= (*token_start++ - '0') * 1;
                                break;
                            default: 
                                PANICf1(depth,token,token_start,parse_ptr,parse_end,"Strange length for negative integer in switch: %d", ch);
                        }
                    } else {
                        goto MAKE_SV;
                    }
                } else {
                    if (ch < 11 ) {
                        switch (ch) {
                            case 10: iv += (*token_start++ - '0') * 1000000000;
                            case  9: iv += (*token_start++ - '0') * 100000000;
                            case  8: iv += (*token_start++ - '0') * 10000000;
                            case  7: iv += (*token_start++ - '0') * 1000000;
                            case  6: iv += (*token_start++ - '0') * 100000;
                            case  5: iv += (*token_start++ - '0') * 10000;
                            case  4: iv += (*token_start++ - '0') * 1000;
                            case  3: iv += (*token_start++ - '0') * 100;
                            case  2: iv += (*token_start++ - '0') * 10;
                            case  1: iv += (*token_start++ - '0') * 1;
                                break;
                            default: 
                                PANICf1(depth,token,token_start,parse_ptr,parse_end,"Strange length for integer in switch: %d", ch);
                        }
                    } else {
                        goto MAKE_SV;
                    }
                }
                got= newSViv(iv);
                goto GOT_SV;
            }
            case TOKEN_NV:
            {
                if (want_key) {
                    DONE_KEY_SIMPLE_break;
                }
                MAKE_SV:
                if (got) {
                    ERROR(depth,token,token_start,parse_ptr,parse_end,"Multiple objects in stream?");
                }
                got= newSVpvn(token_start, parse_ptr - token_start);
                GOT_SV:
                if (obj_char == '{') {
                    if (key) {
                        if (!hv_store((HV*)thing, key, key_len, got, 0)) {
                            PANIC(depth,token,token_start,parse_ptr,parse_end,"failed to store in hash using key/key_len");
                        }
                        got= 0;                                                
                        key= 0;
                    } else if (got_key) {
                        if (!hv_store_ent((HV*)thing, got_key, got, 0)) {
                            PANIC(depth,token,token_start,parse_ptr,parse_end,"failed to store using sv key");
                        }
                        SvREFCNT_dec(got_key);
                        got= 0;                    
                        got_key= 0;
                    } else {
                        PANIC(depth,token,token_start,parse_ptr,parse_end,"got something to store, but no key?");
                    }
                    want_key= 1;
                    allow_comma= 1;
                } else if (obj_char == '[') {
                    /* av_push does not return anything - a little worrying? maybe better to av_store()*/
                    av_push((AV*)thing, got);
                    got= 0;
                    allow_comma= 1;                    
                } else {
                    *parse_start= parse_ptr;
                    return got;
                }
                break;
            }
            default:
                PANICf2(depth,token,token_start,parse_ptr,parse_end,"unhandled token %d '%s'", 
                    token, token_name[token<TOKEN_UNKNOWN ? token : TOKEN_UNKNOWN]);
        }
    } /* while */
    if ( parse_ptr < parse_end ) {
        PANIC(depth,token,token_start,parse_ptr,parse_end,"fallen off the loop with text left");
    } else if (!got) {
        ERRORf1(depth,token,token_start,parse_ptr,parse_end,
            "unterminated %s constructor", obj_char == '{' ? "HASH" : obj_char == '[' ? "ARRAY" : "UNKNOWN");
    } else {
        *parse_start= parse_ptr;
        return got;
    }
}

/* undump a DD style data structure. Takes a plain SV (magic not currently respected)
 * containing a DD Terse/Deepcopy style data dumper output (no $VAR1 = at the front 
 * allowed currently) and returns either undef for a failed parse, or a scalar value
 * of the value parsed.
 *
 * Possible future enhancements:
 * qr//
 * ref to object. Eg \['foo']
 * Make it possible to parse a list instead of a scalar.
 * Blessed objects?
 * Cyclic structures?
 * Less/more tolerant parsing rules?
 * Filters? (Block things by their position in the structure?)
 * Conversion? (IE, we have '[1,1,1]' in the input, and we know we wont need it 
 *    so parse it as '1,1,1' instead.
 */

SV* undump(pTHX_ SV* parse_sv) {
    STRLEN parse_len;
    const char *parse_ptr= SvPV(parse_sv, parse_len);
    const char **parse_start= &parse_ptr;
    const char const *parse_end= parse_ptr + parse_len;
    SV *thing= 0;
    if ( !SvOK(parse_sv) ) {
        sv_setpv(ERRSV,"Bad argument\n");
        return newSV(0);
    } else if (SvLEN(parse_sv) <= parse_len || parse_ptr[parse_len] != 0 ) {
        sv_setpv(ERRSV,"Malformed input string in undump (missing tail null)\n");
        return newSV(0);
    }
    EAT_WHITE(parse_ptr);
    if (parse_ptr<parse_end) {
        thing= _undump(aTHX_ &parse_ptr, parse_end, 0, 0);
        EAT_WHITE(parse_ptr);
    }
    if (thing) {
        if (parse_ptr < parse_end) {
            sv_setpv(ERRSV,"Unhandled tail garbage\n");
            SvREFCNT_dec(thing);
            return newSV(0);
        } else {
            sv_setsv(ERRSV,&PL_sv_undef);
            return thing;
        }
    } else {
        return newSV(0);
    }
}

MODULE = Data::Undump           PACKAGE = Data::Undump

PROTOTYPES: DISABLE


SV *
undump (parse_sv)
        SV *parse_sv
    CODE:
        RETVAL = undump(aTHX_ parse_sv);
    OUTPUT: RETVAL

