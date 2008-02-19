BIBINPUTS:=$(BIBINPUTS):.:../bibtex
TEXINPUTS:=$(TEXINPUTS):.:../bibtex
BSTINPUTS:=$(BSTINPUTS):.:../bibtex

LATEX:=BIBINPUTS=$(BIBINPUTS) TEXINPUTS=$(TEXINPUTS) BSTINPUTS=$(BSTINPUTS) latex
PDFLATEX:=BIBINPUTS=$(BIBINPUTS) TEXINPUTS=$(TEXINPUTS) BSTINPUTS=$(BSTINPUTS) pdflatex
BIBTEX:=BIBINPUTS=$(BIBINPUTS) TEXINPUTS=$(TEXINPUTS) BSTINPUTS=$(BSTINPUTS) bibtex


all: rdtn-tr.pdf 


clean:
	rm -f *.aux *.dvi *.log *~  *.bbl *.blg rdtn-tr.pdf 

%.pdf: %.tex
	rm -f $*.aux
	$(PDFLATEX) $<
	-$(BIBTEX) $*
	$(PDFLATEX) $<
	$(PDFLATEX) $<



