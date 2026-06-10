/* A Bison parser, made by GNU Bison 3.8.2.  */

/* Bison interface for Yacc-like parsers in C

   Copyright (C) 1984, 1989-1990, 2000-2015, 2018-2021 Free Software Foundation,
   Inc.

   This program is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program.  If not, see <https://www.gnu.org/licenses/>.  */

/* As a special exception, you may create a larger work that contains
   part or all of the Bison parser skeleton and distribute that work
   under terms of your choice, so long as that work isn't itself a
   parser generator using the skeleton or a modified version thereof
   as a parser skeleton.  Alternatively, if you modify or redistribute
   the parser skeleton itself, you may (at your option) remove this
   special exception, which will cause the skeleton and the resulting
   Bison output files to be licensed under the GNU General Public
   License without this special exception.

   This special exception was added by the Free Software Foundation in
   version 2.2 of Bison.  */

/* DO NOT RELY ON FEATURES THAT ARE NOT DOCUMENTED in the manual,
   especially those whose name start with YY_ or yy_.  They are
   private implementation details that can be changed or removed.  */

#ifndef YY_HB_COMP_YY_HARBOURY_H_INCLUDED
# define YY_HB_COMP_YY_HARBOURY_H_INCLUDED
/* Debug traces.  */
#ifndef HB_COMP_YYDEBUG
# if defined YYDEBUG
#if YYDEBUG
#   define HB_COMP_YYDEBUG 1
#  else
#   define HB_COMP_YYDEBUG 0
#  endif
# else /* ! defined YYDEBUG */
#  define HB_COMP_YYDEBUG 0
# endif /* ! defined YYDEBUG */
#endif  /* ! defined HB_COMP_YYDEBUG */
#if HB_COMP_YYDEBUG
extern int hb_comp_yydebug;
#endif

/* Token kinds.  */
#ifndef HB_COMP_YYTOKENTYPE
# define HB_COMP_YYTOKENTYPE
  enum hb_comp_yytokentype
  {
    HB_COMP_YYEMPTY = -2,
    HB_COMP_YYEOF = 0,             /* "end of file"  */
    HB_COMP_YYerror = 256,         /* error  */
    HB_COMP_YYUNDEF = 257,         /* "invalid token"  */
    FUNCTION = 258,                /* FUNCTION  */
    PROCEDURE = 259,               /* PROCEDURE  */
    IDENTIFIER = 260,              /* IDENTIFIER  */
    RETURN = 261,                  /* RETURN  */
    NIL = 262,                     /* NIL  */
    LOCAL = 263,                   /* LOCAL  */
    STATIC = 264,                  /* STATIC  */
    IIF = 265,                     /* IIF  */
    IF = 266,                      /* IF  */
    ELSE = 267,                    /* ELSE  */
    ELSEIF = 268,                  /* ELSEIF  */
    END = 269,                     /* END  */
    ENDIF = 270,                   /* ENDIF  */
    ENDERR = 271,                  /* ENDERR  */
    LITERAL = 272,                 /* LITERAL  */
    TRUEVALUE = 273,               /* TRUEVALUE  */
    FALSEVALUE = 274,              /* FALSEVALUE  */
    NUM_DOUBLE = 275,              /* NUM_DOUBLE  */
    INASSIGN = 276,                /* INASSIGN  */
    NUM_LONG = 277,                /* NUM_LONG  */
    ANNOUNCE = 278,                /* ANNOUNCE  */
    EXTERN = 279,                  /* EXTERN  */
    DYNAMIC = 280,                 /* DYNAMIC  */
    AND = 281,                     /* AND  */
    OR = 282,                      /* OR  */
    NOT = 283,                     /* NOT  */
    PUBLIC = 284,                  /* PUBLIC  */
    EQ = 285,                      /* EQ  */
    NE1 = 286,                     /* NE1  */
    NE2 = 287,                     /* NE2  */
    INC = 288,                     /* INC  */
    DEC = 289,                     /* DEC  */
    ALIASOP = 290,                 /* ALIASOP  */
    DOCASE = 291,                  /* DOCASE  */
    CASE = 292,                    /* CASE  */
    OTHERWISE = 293,               /* OTHERWISE  */
    ENDCASE = 294,                 /* ENDCASE  */
    ENDDO = 295,                   /* ENDDO  */
    MEMVAR = 296,                  /* MEMVAR  */
    WHILE = 297,                   /* WHILE  */
    LOOP = 298,                    /* LOOP  */
    EXIT = 299,                    /* EXIT  */
    INIT = 300,                    /* INIT  */
    FOR = 301,                     /* FOR  */
    NEXT = 302,                    /* NEXT  */
    TO = 303,                      /* TO  */
    STEP = 304,                    /* STEP  */
    LE = 305,                      /* LE  */
    GE = 306,                      /* GE  */
    FIELD = 307,                   /* FIELD  */
    IN = 308,                      /* IN  */
    PARAMETERS = 309,              /* PARAMETERS  */
    PLUSEQ = 310,                  /* PLUSEQ  */
    MINUSEQ = 311,                 /* MINUSEQ  */
    MULTEQ = 312,                  /* MULTEQ  */
    DIVEQ = 313,                   /* DIVEQ  */
    POWER = 314,                   /* POWER  */
    EXPEQ = 315,                   /* EXPEQ  */
    MODEQ = 316,                   /* MODEQ  */
    PRIVATE = 317,                 /* PRIVATE  */
    BEGINSEQ = 318,                /* BEGINSEQ  */
    BREAK = 319,                   /* BREAK  */
    RECOVER = 320,                 /* RECOVER  */
    RECOVERUSING = 321,            /* RECOVERUSING  */
    ALWAYS = 322,                  /* ALWAYS  */
    ENDSEQ = 323,                  /* ENDSEQ  */
    DO = 324,                      /* DO  */
    WITH = 325,                    /* WITH  */
    SELF = 326,                    /* SELF  */
    LINE = 327,                    /* LINE  */
    MACROVAR = 328,                /* MACROVAR  */
    MACROTEXT = 329,               /* MACROTEXT  */
    AS_ARRAY = 330,                /* AS_ARRAY  */
    AS_BLOCK = 331,                /* AS_BLOCK  */
    AS_CHARACTER = 332,            /* AS_CHARACTER  */
    AS_CLASS = 333,                /* AS_CLASS  */
    AS_DATE = 334,                 /* AS_DATE  */
    AS_LOGICAL = 335,              /* AS_LOGICAL  */
    AS_NUMERIC = 336,              /* AS_NUMERIC  */
    AS_OBJECT = 337,               /* AS_OBJECT  */
    AS_VARIANT = 338,              /* AS_VARIANT  */
    AS_ARRAY_ARRAY = 339,          /* AS_ARRAY_ARRAY  */
    AS_BLOCK_ARRAY = 340,          /* AS_BLOCK_ARRAY  */
    AS_CHARACTER_ARRAY = 341,      /* AS_CHARACTER_ARRAY  */
    AS_CLASS_ARRAY = 342,          /* AS_CLASS_ARRAY  */
    AS_DATE_ARRAY = 343,           /* AS_DATE_ARRAY  */
    AS_LOGICAL_ARRAY = 344,        /* AS_LOGICAL_ARRAY  */
    AS_NUMERIC_ARRAY = 345,        /* AS_NUMERIC_ARRAY  */
    AS_OBJECT_ARRAY = 346,         /* AS_OBJECT_ARRAY  */
    DECLARE = 347,                 /* DECLARE  */
    OPTIONAL = 348,                /* OPTIONAL  */
    DECLARE_CLASS = 349,           /* DECLARE_CLASS  */
    DECLARE_MEMBER = 350,          /* DECLARE_MEMBER  */
    PROCREQ = 351,                 /* PROCREQ  */
    CBSTART = 352,                 /* CBSTART  */
    DOIDENT = 353,                 /* DOIDENT  */
    FOREACH = 354,                 /* FOREACH  */
    DESCEND = 355,                 /* DESCEND  */
    DOSWITCH = 356,                /* DOSWITCH  */
    ENDSWITCH = 357,               /* ENDSWITCH  */
    WITHOBJECT = 358,              /* WITHOBJECT  */
    ENDWITH = 359,                 /* ENDWITH  */
    NUM_DATE = 360,                /* NUM_DATE  */
    TIMESTAMP = 361,               /* TIMESTAMP  */
    EPSILON = 362,                 /* EPSILON  */
    HASHOP = 363,                  /* HASHOP  */
    THREAD_STATIC = 364,           /* THREAD_STATIC  */
    POST = 365,                    /* POST  */
    UNARY = 366,                   /* UNARY  */
    PRE = 367                      /* PRE  */
  };
  typedef enum hb_comp_yytokentype hb_comp_yytoken_kind_t;
#endif

/* Value type.  */
#if ! defined HB_COMP_YYSTYPE && ! defined HB_COMP_YYSTYPE_IS_DECLARED
union HB_COMP_YYSTYPE
{
#line 126 "c:\\temp\\harbour-core\\src\\compiler\\harbour.y"

   const char * string; /* to hold a string returned by lex */
   int     iNumber;     /* to hold a temporary integer number */
   HB_SIZE sNumber;     /* to hold a temporary HB_SIZE values */
   HB_MAXINT lNumber;   /* to hold a temporary long number */
   HB_BOOL bTrue;
   PHB_EXPR asExpr;
   void * pVoid;        /* to hold any memory structure we may need */
   struct
   {
      HB_MAXINT lNumber;   /* to hold a long number returned by lex */
      HB_UCHAR  bWidth;    /* to hold the width of the value */
   } valLong;
   struct
   {
      double   dNumber;    /* to hold a double number returned by lex */
      HB_UCHAR bWidth;     /* to hold the width of the value */
      HB_UCHAR bDec;       /* to hold the number of decimal points in the value */
   } valDouble;
   struct
   {
      long     date;
      long     time;
   } valTimeStamp;
   struct
   {
      char *   string;
      HB_SIZE  length;
      HB_BOOL  dealloc;
   } valChar;
   struct
   {
      char *   string;
      HB_SIZE  length;
      int      flags;   /* Flag for early {|| &macro} (1) or late {|| &(macro)} (2) binding */
   } asCodeblock;
   PHB_VARTYPE asVarType;

#line 223 "harboury.h"

};
typedef union HB_COMP_YYSTYPE HB_COMP_YYSTYPE;
# define HB_COMP_YYSTYPE_IS_TRIVIAL 1
# define HB_COMP_YYSTYPE_IS_DECLARED 1
#endif




int hb_comp_yyparse (PHB_COMP pComp);


#endif /* !YY_HB_COMP_YY_HARBOURY_H_INCLUDED  */
