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
#define MYDEBUG 0

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

#define COND_ISWHITE(ch) ( (ch) == ' ' || (ch) == '\n' || (ch) == '\t' || (ch) == '\r' )
#define CASE_ISWHITE ' ': case '\n': case '\t': case '\r'
#define EAT_WHITE(p) STMT_START { while ( COND_ISWHITE(*p) ) { p++; } } STMT_END

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




typedef struct parse_state {
    STRLEN string_len;
    const char *string_start;
    const char *string_end;
    SV *parse_sv;
    const char *parse_ptr;
    U32 line_num;
} parse_state;


typedef struct frame_state {
    const char *token_start;
    const char *first_escape;

    const char *key;
    STRLEN key_len;
    SV *thing;
    SV *got_key;
    SV *got;

    U8   token;
    U8 depth;
    char want_key;
    char allow_comma;
    char stop_char;
    char require_fat_comma;
} frame_state;

SV* _undump(pTHX_ parse_state *ps, char obj_char, U8 call_depth);

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

SV* undump(pTHX_ SV* sv) {
    parse_state ps;
    SV *undumped= 0;

    if ( !SvOK(sv) ) {
        sv_setpv(ERRSV,"Bad argument\n");
        return newSV(0);
    }
    ps.parse_sv= sv;
    ps.parse_ptr= ps.string_start= SvPV(sv, ps.string_len);
    ps.string_end= ps.string_start + ps.string_len;
    ps.line_num= 0;

    if ( SvLEN(sv) <= ps.string_len || ps.parse_ptr[ps.string_len] != 0 ) {
        sv_setpv(ERRSV,"Malformed input string in undump (missing tail null)\n");
        return newSV(0);
    }

    EAT_WHITE(ps.parse_ptr);
    if (ps.parse_ptr < ps.string_end) {
        undumped= _undump(aTHX_ &ps, 0, 0);
        EAT_WHITE(ps.parse_ptr);
    }
    if (undumped) {
        if (ps.parse_ptr < ps.string_end) {
            sv_setpv(ERRSV,"Unhandled tail garbage\n");
            SvREFCNT_dec(undumped);
            return newSV(0);
        } else {
            sv_setsv(ERRSV,&PL_sv_undef);
            return undumped;
        }
    } else {
        return newSV(0);
    }
}

#define fs_token           (fs.token)
#define fs_token_start     (fs.token_start)
#define fs_first_escape    (fs.first_escape)

#define fs_want_key        (fs.want_key)
#define fs_allow_comma     (fs.allow_comma)
#define fs_require_fat_comma     (fs.require_fat_comma)
#define fs_stop_char       (fs.stop_char)
#define fs_key             (fs.key)
#define fs_key_len         (fs.key_len)
#define fs_thing           (fs.thing)
#define fs_got_key         (fs.got_key)
#define fs_got             (fs.got)
#define fs_depth           (fs.depth)

#define ps_parse_sv        (ps->parse_sv)
#define ps_string_start    (ps->string_start)
#define ps_string_end      (ps->string_end)
#define ps_string_len      (ps->string_len)
#define ps_parse_ptr       (ps->parse_ptr)
#define ps_line_num        (ps->line_num)

#define DEPTH(D,T) ( ( (D) * 4 ) + ( ( (T) == TOKEN_OPEN || (T) == TOKEN_BLESS ) - ( (T) == TOKEN_CLOSE ) ) * 2 )

#define BAIL(ps,fs) STMT_START { \
    if(fs_got) SvREFCNT_dec(fs_got);  \
    if(fs_got_key) SvREFCNT_dec(fs_got_key);  \
    if(fs_thing) SvREFCNT_dec(fs_thing);  \
    return 0; \
} STMT_END



#define SHOW_POSITION( ps, fs, show_len ) STMT_START {\
    int remaining= (ps_string_end) - (ps_parse_ptr);  \
    int token_len= (ps_parse_ptr) - (fs_token_start); \
    int backup_len=0;\
    const char *backup_pos;\
    if (ps_string_start < fs_token_start) { \
        backup_len= fs_token_start - ps_string_start; \
        if (backup_len > show_len) { \
            backup_len= show_len; \
        } \
        backup_pos= fs_token_start - backup_len; \
    } else { \
        backup_pos= 0; \
    } \
    warn("%*sprior:'%.*s'\n"                \
         "%*stoken:'%.*s'%s\n"              \
         "%*sto-go:'%.*s'%s\n\n",             \
        DEPTH((fs_depth),(fs_token)), "",         \
        backup_len, backup_pos,             \
        DEPTH((fs_depth),(fs_token)), "",         \
        ( ( token_len > (show_len) ) ? (show_len) : token_len) , (fs_token_start), \
        ( ( token_len > (show_len) ) ? "..." : ""), \
        DEPTH((fs_depth),(fs_token)), "", \
        ( ( remaining > (show_len) ) ? (show_len) : remaining ) , (ps_parse_ptr), \
        ( ( remaining > (show_len) ) ? "..." : "") \
    ); \
} STMT_END

#define PANIC(ps,fs,X) STMT_START { \
    if (MYDEBUG) { \
        warn("%*s%s\n",DEPTH((fs_depth),(fs_token)) , "", (X)); \
        SHOW_POSITION(ps,fs, 32); \
    } \
    sv_setpvf( ERRSV, "%s\n", (X) ); \
    BAIL(ps,fs);\
} STMT_END

#define PANICf1(ps,fs,F,X) STMT_START { \
    if (MYDEBUG) { \
        warn("%*s" F "\n",DEPTH((fs_depth),(fs_token)),"", (X)); \
        SHOW_POSITION(ps,fs, 32); \
    }\
    sv_setpvf( ERRSV, F "\n", (X) ); \
    BAIL(ps,fs);\
} STMT_END

#define PANICf2(ps,fs,F,X,Y) STMT_START { \
    if (MYDEBUG) { \
        warn("%*s" F "\n",DEPTH((fs_depth),(fs_token)),"", (X),(Y)); \
        SHOW_POSITION(ps,fs, 32); \
    } \
    sv_setpvf( ERRSV, F "\n", (X), (Y)); \
    BAIL(ps,fs);\
} STMT_END

#define ERROR(ps,fs,X) STMT_START { \
    if (MYDEBUG>1) { \
        warn("%*s%s\n",DEPTH((fs_depth),(fs_token)) , "", (X)); \
        SHOW_POSITION(ps,fs, 32); \
    } \
    sv_setpvf( ERRSV, "%s\n", (X) ); \
    BAIL(ps,fs);\
} STMT_END

#define ERRORf1(ps,fs,F,X) STMT_START { \
    if (MYDEBUG>1) { \
        warn("%*s" F "\n",DEPTH((fs_depth),(fs_token)),"", (X)); \
        SHOW_POSITION(ps,fs, 32); \
    } \
    sv_setpvf( ERRSV, F "\n", (X) ); \
    BAIL(ps,fs);\
} STMT_END

#define ERRORf2(ps, fs, F,X,Y) STMT_START { \
    if (MYDEBUG>1) { \
        warn("%*s" F "\n",DEPTH((fs_depth),(fs_token)),"", (X),(Y)); \
        SHOW_POSITION(ps, fs, 32); \
    } \
    sv_setpvf( ERRSV, F "\n", (X), (Y)); \
    BAIL(ps,fs);\
} STMT_END

#define SHOW_TOKEN(ps,fs) \
    if (MYDEBUG>1) warn("%*s%-2d %*s %.*s\n", DEPTH((fs_depth), (fs_token)), "", \
         fs_token, -20,  token_name[((fs_token)<TOKEN_UNKNOWN) ? (fs_token) : TOKEN_UNKNOWN ],(int)((ps_parse_ptr) - (fs_token_start)), (fs_token_start))


#define DONE_KEY_break                      \
        fs_want_key= 0;                        \
        fs_allow_comma= 1;                     \
        break
#define DONE_KEY_SIMPLE_break               \
        fs_key= fs_token_start;                   \
        fs_key_len= ps_parse_ptr - fs_token_start;   \
        DONE_KEY_break                      

/* recursively undump a DD style dump 
 * 
 * If called with an obj_char then we are building an object of that type, otherwise we are searching for
 * a new value. When we encounter a '[' we gobble it up and then call the child with '[' as the obj_char
 * where it then parses until it encounters a ']' which it eats, and then return whatever it built.
 *
 * We restrict to objects nested 100 items deep.
 *
 * If anything bogus in the input stream is encountered we free everything created so far, and return 0 
 * to unwind.
 *
 * Returns either an SV or NULL indicating an error.
 *
 */
SV* _undump(pTHX_ parse_state *ps, char obj_char, U8 call_depth) {
    char ch= 0;
    frame_state fs;

    fs_token= TOKEN_ERROR;
    fs_want_key= 0;
    fs_allow_comma= 0;
    fs_stop_char= 0;
    fs_require_fat_comma= 0;
    fs_key= 0;
    fs_key_len= 0;
    fs_thing= 0;
    fs_got_key= 0;
    fs_got= 0;
    fs_depth= call_depth;

    if (call_depth > 100) {
        PANIC(ps,fs,"Structure is nested too deep");
    }

    if (!obj_char) {
        fs_stop_char= 0;
    } else if (obj_char == '[') {
        fs_thing= (SV*)newAV();
        fs_stop_char= ']';
    } else if (obj_char == '{') {
        fs_key= 0;
        fs_key_len= 0;
        fs_thing= (SV*)newHV();
        fs_want_key= 1;
        fs_stop_char= '}';
    } else {
        PANICf1(ps,fs, "Unknown obj char '%c'", obj_char);
    }

  REPARSE:
    while ( ps_parse_ptr < ps_string_end) {
        fs_token_start= ps_parse_ptr;
        fs_token= TOKEN_ERROR;
        ch= *(ps_parse_ptr++);
        switch (ch) {
            case CASE_ISWHITE:
                EAT_WHITE(ps_parse_ptr);
                goto REPARSE;
            case '=':
                if ( *ps_parse_ptr != '>' ) {
                    ERROR(ps,fs,"Encountered assignment '=' or unterminated fat comma '=>'");
                }
                fs_require_fat_comma = 0;
                ps_parse_ptr++;
                /* fallthrough */
            case ',': 
                /* comma */
                if ( fs_require_fat_comma ) {
                    ERROR(ps,fs,"expected fat comma after bareword");
                }
                else if ( ! fs_allow_comma ) {
                    ERRORf2(ps,fs,"unexpected %s when expecting a %s",
                        (ch=='=' ? "fat comma" : "comma"),(fs_want_key ? "key" : "value"));
                }
                fs_allow_comma = 0;
                goto REPARSE;
            case '$': 
            case '%': 
            case '@': 
                ps_parse_ptr--;
                ERROR(ps,fs,"Encountered variable in input. This is not eval - can not undump code");
            case '{':
            case '[':
                fs_token= TOKEN_OPEN;
                break;
            case ']':
            case '}':
                fs_token= TOKEN_CLOSE;
                break;
            case '\'':
                fs_first_escape= 0;
                while (ps_parse_ptr < ps_string_end && *ps_parse_ptr != '\'') {
                    /* check if its a valid escape */
                    if (*ps_parse_ptr == '\\' && (ps_parse_ptr[1] == '\\' || ps_parse_ptr[1] == '\'')) {
                        if (!fs_first_escape)
                            fs_first_escape= ps_parse_ptr;
                        ps_parse_ptr++;
                    }
                    ps_parse_ptr++;
                    
                }
                if (ps_parse_ptr >= ps_string_end) {
                    ERROR(ps,fs,"unterminated single quoted string");
                }
                assert(*ps_parse_ptr == ch);
                ps_parse_ptr++; /* skip over the trailing quote */
                fs_token= TOKEN_Q_STRING;
                break;
            case '\"':
                /* quoted */
                fs_first_escape= 0;
                while (ps_parse_ptr < ps_string_end && *ps_parse_ptr != ch) {
                    if (*ps_parse_ptr == '\\') { /* if its an escape pull off the backslash */
                        if (!fs_first_escape)
                            fs_first_escape= ps_parse_ptr;
                        ps_parse_ptr++;
                    } else if (*ps_parse_ptr == '$' || *ps_parse_ptr == '@') {
                        ERROR(ps,fs,"Unescaped '$' and '@' are illegal in double quoted strings");
                    }
                    ps_parse_ptr++;
                }
                if (ps_parse_ptr >= ps_string_end) {
                    ERROR(ps,fs,"unterminated double quoted string");
                }
                assert(*ps_parse_ptr == ch);
                ps_parse_ptr++; /* skip over the trailing quote */
                fs_token= TOKEN_QQ_STRING;
                break;
            case '-':
                ch= *ps_parse_ptr;
                if ( '0' == ch ) {
                    ps_parse_ptr++;
                    if (*ps_parse_ptr != '.') {
                        ERROR(ps,fs,"Negative number start with a zero that is not fractional is illegal");
                    }
                    goto DO_DECIMAL;
                } else if ( '1' <= ch && ch <= '9' ) {
                    ps_parse_ptr++;
                } else {
                    ERROR(ps,fs,"bare '-' only allowed to signify negative number");
                }
                goto DO_NUMBER;
            case '0':
                if ( ps_parse_ptr < ps_string_end && ('0' <= *ps_parse_ptr && *ps_parse_ptr <= '9')) {
                    ERROR(ps,fs,"Zero may not be followed by another digit at the start of a number");
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
                ch= *ps_parse_ptr;
                while ( '0' <= ch && ch <= '9' ) {
                    ch= *(++ps_parse_ptr);
                }
                if ( ch == '.' ) {
                  DO_DECIMAL:
                    ch= *(++ps_parse_ptr);
                    if ( '0' <= ch && ch <= '9' ) {
                        ch= *(++ps_parse_ptr);
                    } else {
                        ERROR(ps,fs,"Unexpected end of floating point number after decimal point");
                    }
                    while ('0' <= ch && ch <= '9') {
                        ch= *(++ps_parse_ptr);
                    }
                    fs_token= TOKEN_NV;
                } else {
                    fs_token= TOKEN_IV;
                }
                break;
            default: 
                if (bareword_start[(U8)ch]) {
                    ch= *ps_parse_ptr;
                    while ( bareword_rest[(U8)ch] ) {
                        ch= *(++ps_parse_ptr);
                    }
                } else {
                    ps_parse_ptr--;
                    PANICf2(ps,fs,"Unexpected character '%c' codepoint 0x%02x while parsing bareword",ch,ch);
                }
                /* for some reason all the interesting keywords are 5 characters long */
                if ( 5 == (ps_parse_ptr - fs_token_start) ) {
                    if ( 
                         'b' == fs_token_start[0] &&
                         'l' == fs_token_start[1] &&
                         'e' == fs_token_start[2] &&
                         's' == fs_token_start[3] &&
                         's' == fs_token_start[4]
                    ){
                        fs_token= TOKEN_BLESS;
                    } else if ( 
                         'u' == fs_token_start[0] &&
                         'n' == fs_token_start[1] &&
                         'd' == fs_token_start[2] &&
                         'e' == fs_token_start[3] &&
                         'f' == fs_token_start[4]
                    ){
                        fs_token= TOKEN_UNDEF;
                    } else { 
                        fs_token= TOKEN_BAREWORD;
                    }
                } else {
                    fs_token= TOKEN_BAREWORD;
                }
        } /* switch */
        if (fs_require_fat_comma) {
            ERROR(ps,fs,"expected fat comma after bareword");
        } else if (fs_allow_comma && fs_token != TOKEN_CLOSE) {
            ERRORf1(ps,fs,"Expecting comma got %s",token_name[fs_token]);
        }
        SHOW_TOKEN(ps,fs);
        switch (fs_token) {
            case TOKEN_BLESS:
                if ( *ps_parse_ptr != '(') {
                    ERROR(ps,fs,"expected a '(' after 'bless'");
                } else {
                    ps_parse_ptr++;
                    /* ERROR(ps,fs,"after bless("); */
                }
                if (fs_want_key) {
                    ERRORf1(ps,fs,"unexpected bless() call when expecting a key", ch);
                }
                ch= 0; /* flag for blessing */
            case TOKEN_OPEN:
                if (fs_want_key) {
                    ERRORf1(ps,fs,"unexpected open bracket '%c' when expecting a key", ch);
                }
                if (fs_got) {
                    ERROR(ps,fs,"Multiple objects in stream?");
                }
                fs_got= _undump( aTHX_ ps, ch, call_depth+1);
                if (!fs_got) {
                    BAIL(ps,fs);
                } else {
                    if ( ch == 0 ) {
                        char quote;
                        HV *stash;
                        EAT_WHITE(ps_parse_ptr);
                        if (*ps_parse_ptr == ',') {
                            ps_parse_ptr++;
                            EAT_WHITE(ps_parse_ptr);
                        } else {
                            ERROR(ps,fs,"expected a comma after object in bless()");
                        }
                        ch= *ps_parse_ptr;
                        if ( ch != '\'' && ch != '\"') {
                            ERROR(ps,fs,"Expected quoted class name after object in bless()");
                        }
                        quote = ch;
                        fs_token_start= ++ps_parse_ptr;
                        if (!bareword_start[(U8)*ps_parse_ptr]) {
                            ERROR(ps,fs,"Expected classname to start with [A-Za-z_]");
                        }
                        do { 
                            ch= *(++ps_parse_ptr);
                            if (ch == ':') {
                                ch= *(++ps_parse_ptr);
                                if (ch != ':') {
                                    ERROR(ps,fs,"Single colon in class name?");
                                } else {
                                    ch= *(++ps_parse_ptr);
                                }
                            }
                        } 
                        while (bareword_rest[(U8)ch]);
                        if (ch != quote) {
                            ERROR(ps,fs,"Unterminated or corrupt classname");
                        } 

                        /* XXX: mortalize 'got; here? can this die? */
                        stash= gv_stashpvn(fs_token_start, ps_parse_ptr - fs_token_start, 1);
                        if (!stash) {
                            PANIC(ps,fs,"Failed to load stash");
                        }
                        ++ps_parse_ptr; /* skip quote */
                        EAT_WHITE(ps_parse_ptr); /* eat optional whitespace after quote */
                        ch= *ps_parse_ptr; /* check we have a close paren */
                        if (ch != ')') {
                            ERRORf1(ps,fs,"expecting a close paren for bless but got a '%c'",ch);
                        } else {
                            ps_parse_ptr++;
                        }
                        /* and finally do the blessing */
                        if(0) do_sv_dump(0, Perl_debug_log, fs_got, 0, 4, 0, 0);
                        sv_bless(fs_got,stash);
                        if(0) do_sv_dump(0, Perl_debug_log, fs_got, 0, 4, 0, 0);
                        
                    }
                    goto GOT_SV;
                }     
                /* unreached */           
                break;
            case TOKEN_CLOSE:
            {
                if (fs_stop_char == ch) {
                    if (fs_got_key || fs_key) {
                        ERROR(ps,fs,"Odd number of items in hash constructor");
                    }
                    return  newRV((SV *)fs_thing);
                } else if (!fs_stop_char) {
                    ERRORf1(ps,fs,"Unexpected close bracket '%c'",ch);
                } else {
                    ERRORf2(ps,fs,"Unexpected close '%c' while parsing %s",
                            ch, (fs_stop_char == '}') ? "HASH" : "ARRAY");
                } 
                break;
            }
            case TOKEN_UNDEF:
                if (fs_want_key) {
                    ERROR(ps,fs,"got an undef when we wanted a key");
                }
                if (fs_got) {
                    ERROR(ps,fs,"Multiple objects in stream?");
                }
                fs_got= newSV(0);
                goto GOT_SV;
                /* unreached */
                break;
                                
            case TOKEN_Q_STRING:
            case TOKEN_QQ_STRING:{
                /* nothing to unescape - we are done now */
                fs_token_start++; /* skip the first quote */
                if ( !fs_first_escape ) {
                    /* it didnt contain any escapes */
                    if ( fs_want_key ) {
                        fs_key= fs_token_start;
                        fs_key_len= ps_parse_ptr - fs_token_start - 1; /* remove trailing quote */
                        fs_want_key= 0;
                        fs_allow_comma= 1;
                        break;
                    }
                    if (fs_got) {
                        ERROR(ps,fs,"Multiple objects in stream?");
                    }
                    fs_got= newSVpvn(fs_token_start, ps_parse_ptr - fs_token_start - 1); /* remove trailing quote */
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
                                
                    if (fs_got) {
                        ERROR(ps,fs,"Multiple objects in stream?");
                    }
                    /* create a new SV with a copy of the raw escaped string in it - with octal
                       this is sufficient to guarantee enough space to unescape, with \x{} style
                       escapes things are more complicated */

                    fs_got= newSVpvn(fs_token_start, ps_parse_ptr - fs_token_start - 1); /* remove trailing quote */
                    /* the sv now contains a copy of the unescaped string */ 

                    new_str_begin= SvPV(fs_got, new_len);
                    new_str_end= new_str_begin + new_len;
                    esc_read= esc_write= new_str_begin + ( fs_first_escape - fs_token_start );
                    if (*esc_write != '\\') {
                        PANIC(ps,fs,"when parsing quoted string failed start quote sanity check");
                    }
                    if (fs_token == TOKEN_Q_STRING) {
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
                                    PANIC(ps,fs,"ran off end of string");
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
                                            ERROR(ps,fs,"truncated \\x{} sequence?");
                                        } else {
                                            esc_read++;
                                        }
                                        grok_start= esc_read;
                                        while (*esc_read && *esc_read != '}') esc_read++;
                                        if (*esc_read != '}') {
                                            ERROR(ps,fs,"unterminated \\x{} in double quoted string");
                                        } else {
                                            grok_len= esc_read - grok_start;
                                            esc_read++; /* skip '}' */
                                        }
                                        /* warn("hex: %.*s\n", grok_len, grok_start); */
                                        if (grok_len) {
                                            cp= grok_hex((char *)grok_start, &grok_len, &grok_flags, 0);
                                        } else {
                                            ERROR(ps,fs,"empty \\x{} escape?");
                                        }
                                        /* warn("cp: %d\n len: %d flags: %d", cp, grok_len, grok_flags); */
                                        if ( cp < 0x100 ) { /* otherwise it would be in octal */
                                            must_uni= 1;
                                        }
                                        if (cp>0x10FFFF) {
                                            ERRORf1(ps,fs,"Illegal codepoint in \\x{%x}",cp);
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
                                sv_catpvf(fs_got, "%c", cp);
                            } else if (cp < 256) {
                                *esc_write++= (char)cp;
                            } else {
                                SvCUR_set(fs_got, esc_write - new_str_begin);
                                is_uni= 1;
                                sv_catpvf(fs_got, "%c", cp);
                            }
                        } /* while */
                    }  /* TOKEN_Q_STRING or TOKEN_QQ_STRING */
                    if (!is_uni) {
                        SvCUR_set(fs_got, esc_write - new_str_begin);
                        *esc_write++= 0;
                        if (must_uni && !is_uni) {
                            sv_utf8_upgrade(fs_got);
                        }
                    }
                    if (fs_want_key) {
                        /* we contain stuff that will be used as a hash key lookup */
                        fs_got_key= fs_got;   /* swap got over to the got_key var for later */
                        fs_key= 0;         /* make sure we dont get confused about two keys */
                        fs_got= 0;         /* clear got */
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
                fs_require_fat_comma= 1;
                if (fs_want_key) {
                    DONE_KEY_SIMPLE_break;
                }
                if (fs_got) {
                    ERROR(ps,fs,"Multiple objects in stream?");
                }
                fs_got= newSVpvn(fs_token_start, ps_parse_ptr - fs_token_start);
                goto GOT_SV;
            case TOKEN_IV:{
                IV iv;
                
                /* fallthrough */
                if (fs_want_key) {
                    DONE_KEY_SIMPLE_break;
                } 
                iv= 0;
                ch= ps_parse_ptr - fs_token_start;
                if (fs_token_start[0] == '-') {
                    if ( ch < 12) {
                        fs_token_start++;
                        switch (ch) {
                            case 11: iv -= (*fs_token_start++ - '0') * 1000000000;
                            case 10: iv -= (*fs_token_start++ - '0') * 100000000;
                            case  9: iv -= (*fs_token_start++ - '0') * 10000000;
                            case  8: iv -= (*fs_token_start++ - '0') * 1000000;
                            case  7: iv -= (*fs_token_start++ - '0') * 100000;
                            case  6: iv -= (*fs_token_start++ - '0') * 10000;
                            case  5: iv -= (*fs_token_start++ - '0') * 1000;
                            case  4: iv -= (*fs_token_start++ - '0') * 100;
                            case  3: iv -= (*fs_token_start++ - '0') * 10;
                            case  2: iv -= (*fs_token_start++ - '0') * 1;
                                break;
                            default: 
                                PANICf1(ps,fs,"Strange length for negative integer in switch: %d", ch);
                        }
                    } else {
                        goto MAKE_SV;
                    }
                } else {
                    if (ch < 11 ) {
                        switch (ch) {
                            case 10: iv += (*fs_token_start++ - '0') * 1000000000;
                            case  9: iv += (*fs_token_start++ - '0') * 100000000;
                            case  8: iv += (*fs_token_start++ - '0') * 10000000;
                            case  7: iv += (*fs_token_start++ - '0') * 1000000;
                            case  6: iv += (*fs_token_start++ - '0') * 100000;
                            case  5: iv += (*fs_token_start++ - '0') * 10000;
                            case  4: iv += (*fs_token_start++ - '0') * 1000;
                            case  3: iv += (*fs_token_start++ - '0') * 100;
                            case  2: iv += (*fs_token_start++ - '0') * 10;
                            case  1: iv += (*fs_token_start++ - '0') * 1;
                                break;
                            default: 
                                PANICf1(ps,fs,"Strange length for integer in switch: %d", ch);
                        }
                    } else {
                        goto MAKE_SV;
                    }
                }
                fs_got= newSViv(iv);
                goto GOT_SV;
            }
            case TOKEN_NV:
            {
                if (fs_want_key) {
                    DONE_KEY_SIMPLE_break;
                }
                MAKE_SV:
                if (fs_got) {
                    ERROR(ps,fs,"Multiple objects in stream?");
                }
                fs_got= newSVpvn(fs_token_start, ps_parse_ptr - fs_token_start);
                GOT_SV:
                if (obj_char == '{') {
                    if (fs_key) {
                        if (!hv_store((HV*)fs_thing, fs_key, fs_key_len, fs_got, 0)) {
                            PANIC(ps,fs,"failed to store in hash using key/key_len");
                        }
                        fs_got= 0;
                        fs_key= 0;
                    } else if (fs_got_key) {
                        if (!hv_store_ent((HV*)fs_thing, fs_got_key, fs_got, 0)) {
                            PANIC(ps,fs,"failed to store using sv key");
                        }
                        SvREFCNT_dec(fs_got_key);
                        fs_got= 0;
                        fs_got_key= 0;
                    } else {
                        PANIC(ps,fs,"got something to store, but no key?");
                    }
                    fs_want_key= 1;
                    fs_allow_comma= 1;
                } else if (obj_char == '[') {
                    /* av_push does not return anything - a little worrying? maybe better to av_store()*/
                    av_push((AV*)fs_thing, fs_got);
                    fs_got= 0;
                    fs_allow_comma= 1;
                } else {
                    return fs_got;
                }
                break;
            }
            default:
                PANICf2(ps,fs,"unhandled fs_token %d '%s'",
                    fs_token, token_name[fs_token<TOKEN_UNKNOWN ? fs_token : TOKEN_UNKNOWN]);
        }
    } /* while */
    if ( ps_parse_ptr < ps_string_end ) {
        PANIC(ps,fs,"fallen off the loop with text left");
    } else if (!fs_got) {
        ERRORf1(ps,fs,
            "unterminated %s constructor", obj_char == '{' ? "HASH" : obj_char == '[' ? "ARRAY" : "UNKNOWN");
    } else {
        return fs_got;
    }
}


MODULE = Data::Undump           PACKAGE = Data::Undump

PROTOTYPES: DISABLE


SV *
undump (sv)
        SV *sv
    CODE:
        RETVAL = undump(aTHX_ sv);
    OUTPUT: RETVAL

