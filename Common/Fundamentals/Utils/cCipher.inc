{******************************************************************************}
{                                                                              }
{   Library:          Fundamentals 4.00                                        }
{   File name:        cCipher.inc                                              }
{   Description:      Cipher library defines                                   }
{                                                                              }
{******************************************************************************}

{.DEFINE DEBUG}
{.DEFINE SELFTEST}

{$INCLUDE cDefines.inc}

{$IFDEF DEBUG}
{$IFDEF SELFTEST}
  {$DEFINE CIPHER_SELFTEST}
{$ENDIF}
{$ENDIF}

