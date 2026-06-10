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

#ifndef YY_HB_MACRO_YY_MACROY_H_INCLUDED
# define YY_HB_MACRO_YY_MACROY_H_INCLUDED
/* Debug traces.  */
#ifndef HB_MACRO_YYDEBUG
# if defined YYDEBUG
#if YYDEBUG
#   define HB_MACRO_YYDEBUG 1
#  else
#   define HB_MACRO_YYDEBUG 0
#  endif
# else /* ! defined YYDEBUG */
#  define HB_MACRO_YYDEBUG 0
# endif /* ! defined YYDEBUG */
#endif  /* ! defined HB_MACRO_YYDEBUG */
#if HB_MACRO_YYDEBUG
extern int hb_macro_yydebug;
#endif

/* Token kinds.  */
#ifndef HB_MACRO_YYTOKENTYPE
# define HB_MACRO_YYTOKENTYPE
  enum hb_macro_yytokentype
  {
    HB_MACRO_YYEMPTY = -2,
    HB_MACRO_YYEOF = 0,            /* "end of file"  */
    HB_MACRO_YYerror = 256,        /* error  */
    HB_MACRO_YYUNDEF = 257,        /* "invalid token"  */
    IDENTIFIER = 258,              /* IDENTIFIER  */
    NIL = 259,                     /* NIL  */
    NUM_DOUBLE = 260,              /* NUM_DOUBLE  */
    INASSIGN = 261,                /* INASSIGN  */
    NUM_LONG = 262,                /* NUM_LONG  */
    NUM_DATE = 263,                /* NUM_DATE  */
    TIMESTAMP = 264,               /* TIMESTAMP  */
    IIF = 265,                     /* IIF  */
    LITERAL = 266,                 /* LITERAL  */
    TRUEVALUE = 267,               /* TRUEVALUE  */
    FALSEVALUE = 268,              /* FALSEVALUE  */
    AND = 269,                     /* AND  */
    OR = 270,                      /* OR  */
    NOT = 271,                     /* NOT  */
    EQ = 272,                      /* EQ  */
    NE1 = 273,                     /* NE1  */
    NE2 = 274,                     /* NE2  */
    INC = 275,                     /* INC  */
    DEC = 276,                     /* DEC  */
    ALIASOP = 277,                 /* ALIASOP  */
    HASHOP = 278,                  /* HASHOP  */
    SELF = 279,                    /* SELF  */
    LE = 280,                      /* LE  */
    GE = 281,                      /* GE  */
    FIELD = 282,                   /* FIELD  */
    MACROVAR = 283,                /* MACROVAR  */
    MACROTEXT = 284,               /* MACROTEXT  */
    PLUSEQ = 285,                  /* PLUSEQ  */
    MINUSEQ = 286,                 /* MINUSEQ  */
    MULTEQ = 287,                  /* MULTEQ  */
    DIVEQ = 288,                   /* DIVEQ  */
    POWER = 289,                   /* POWER  */
    EXPEQ = 290,                   /* EXPEQ  */
    MODEQ = 291,                   /* MODEQ  */
    EPSILON = 292,                 /* EPSILON  */
    POST = 293,                    /* POST  */
    UNARY = 294,                   /* UNARY  */
    PRE = 295                      /* PRE  */
  };
  typedef enum hb_macro_yytokentype hb_macro_yytoken_kind_t;
#endif

/* Value type.  */
#if ! defined HB_MACRO_YYSTYPE && ! defined HB_MACRO_YYSTYPE_IS_DECLARED
union HB_MACRO_YYSTYPE
{
#line 140 "c:\\temp\\harbour-core\\src\\macro\\macro.y"

   const char * string; /* to hold a string returned by lex */
   int       iNumber;   /* to hold a temporary integer number */
   HB_MAXINT lNumber;   /* to hold a temporary long number */
   void *    pVoid;     /* to hold any memory structure we may need */
   PHB_EXPR  asExpr;
   struct
   {
      const char * string;
      HB_SIZE      length;
   } valChar;
   struct
   {
      int      iNumber; /* to hold a number returned by lex */
   } valInteger;
   struct
   {
      HB_MAXINT lNumber; /* to hold a long number returned by lex */
      HB_UCHAR  bWidth;  /* to hold the width of the value */
   } valLong;
   struct
   {
      double   dNumber; /* to hold a double number returned by lex */
      HB_UCHAR bWidth;  /* to hold the width of the value */
      HB_UCHAR bDec;    /* to hold the number of decimal points in the value */
   } valDouble;
   struct
   {
      long     date;    /* to hold Julian date */
      long     time;    /* to hold milliseconds */
   } valTimeStamp;

#line 145 "macroy.h"

};
typedef union HB_MACRO_YYSTYPE HB_MACRO_YYSTYPE;
# define HB_MACRO_YYSTYPE_IS_TRIVIAL 1
# define HB_MACRO_YYSTYPE_IS_DECLARED 1
#endif




int hb_macro_yyparse (PHB_MACRO pMacro);


#endif /* !YY_HB_MACRO_YY_MACROY_H_INCLUDED  */
